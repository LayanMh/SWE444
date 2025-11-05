import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class GeneratePdfPage extends StatefulWidget {
  final String myRequestId;
  const GeneratePdfPage({super.key, required this.myRequestId});

  @override
  State<GeneratePdfPage> createState() => _GeneratePdfPageState();
}

// ───────────────────────────── Models ─────────────────────────────
class _CourseRow {
  final String code;
  final String section;
  final String name;
  final int hours;
  const _CourseRow({
    required this.code,
    required this.section,
    required this.name,
    required this.hours,
  });
}

class _FormData {
  final String studentName;
  final String studentId;
  final String studentEmail;
  final String studentMajor;
  final List<_CourseRow> additions;
  final List<_CourseRow> deletions;
  final int beforeHours;
  final int afterHours;

  const _FormData({
    required this.studentName,
    required this.studentId,
    required this.studentEmail,
    required this.studentMajor,
    required this.additions,
    required this.deletions,
    required this.beforeHours,
    required this.afterHours,
  });
}

// ───────────────────────────── Main Widget ─────────────────────────────
class _GeneratePdfPageState extends State<GeneratePdfPage> {
  bool _loading = false;
  Uint8List? _pdfBytes;
  String? _errorMessage;
  late final TransformationController _zoomController;
  double _zoomScale = 1.0;
  bool _isUpdatingZoom = false;

  static const double _minZoom = 0.8;
  static const double _maxZoom = 2.5;

  @override
  void initState() {
    super.initState();
    _zoomController = TransformationController();
    _zoomController.addListener(_handleZoomControllerChange);
    _resetZoom(notify: false);
    _generatePdf();
  }

  @override
  void dispose() {
    _zoomController.removeListener(_handleZoomControllerChange);
    _zoomController.dispose();
    super.dispose();
  }

  // ─────────────── Firestore Fetch Helpers ───────────────
  Future<Map<String, dynamic>?> _fetchSwapRequest(String id) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('swap_requests').doc(id).get();
      return doc.data();
    } catch (e) {
      debugPrint('🔥 Error fetching swap request $id: $e');
      return null;
    }
  }

  Future<List<_CourseRow>> _fetchGroupCourses(
      dynamic groupField, {
        String? major,
        dynamic level,
      }) async {
    if (groupField == null) return [];

    int? groupNumber = groupField is int ? groupField : int.tryParse('$groupField');
    if (groupNumber == null) return [];

    try {
      debugPrint('🔎 Fetching group with Number=$groupNumber, Major=$major, Level=$level');
      final ref = FirebaseFirestore.instance.collection('Groups');

      Query<Map<String, dynamic>> query = ref.where('Number', isEqualTo: groupNumber);
      if (major != null) query = query.where('Major', isEqualTo: major);
      if (level != null) query = query.where('Level', isEqualTo: level);

      final snap = await query.limit(1).get();
      if (snap.docs.isEmpty) return [];

      final data = snap.docs.first.data();
      final rawSections = (data['sections'] ?? data['Sections']) as List<dynamic>?;

      if (rawSections == null || rawSections.isEmpty) {
        debugPrint('⚠️ Group $groupNumber has no sections.');
        return [];
      }

      return await _fetchSectionCourses(rawSections.map((e) => e.toString()).toList());
    } catch (e) {
      debugPrint('🔥 Error fetching group: $e');
      return [];
    }
  }

  Future<List<_CourseRow>> _fetchSectionCourses(List<String> sections) async {
    final results = <_CourseRow>[];
    for (final s in sections) {
      try {
        final q = await FirebaseFirestore.instance
            .collection('timetables')
            .where('section', isEqualTo: s)
            .limit(1)
            .get();
        if (q.docs.isEmpty) continue;
        final d = q.docs.first.data();
        results.add(_CourseRow(
          code: (d['courseCode'] ?? '').toString(),
          section: (d['section'] ?? '').toString(),
          name: (d['courseName'] ?? '').toString(),
          hours: int.tryParse('${d['hour'] ?? 0}') ?? 0,
        ));
      } catch (e) {
        debugPrint('🔥 Error fetching section $s: $e');
      }
    }
    return results;
  }

  List<String> _normalize(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      final values = <String>[];
      for (final item in raw) {
        if (item == null) continue;
        final value = item.toString().trim();
        if (value.isNotEmpty) values.add(value);
      }
      return values;
    }
    if (raw is String) {
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((value) => value.isNotEmpty)
          .toList();
    }
    return [];
  }

  List<String> _extractSections(dynamic raw) {
    if (raw == null) return [];
    if (raw is String) {
      return raw
          .split(',')
          .map((e) => e.trim())
          .where((value) => value.isNotEmpty)
          .toList();
    }
    if (raw is! List) return [];

    final sections = <String>[];
    for (final item in raw) {
      if (item is Map) {
        final section = item['section'] ?? item['Section'];
        if (section != null) {
          final value = section.toString().trim();
          if (value.isNotEmpty) sections.add(value);
          continue;
        }
      }
      if (item == null) continue;
      final value = item.toString().trim();
      if (value.isNotEmpty) sections.add(value);
    }
    return sections;
  }

  int _sumHours(List<_CourseRow> rows) =>
      rows.fold<int>(0, (total, row) => total + row.hours);

  // ─────────────── Build Form Data ───────────────
  Future<_FormData> _buildFormData(
      Map<String, dynamic> req, Map<String, dynamic>? partner) async {
    final major = req['major'] ?? req['Major'] ?? 'Software Engineering';
    final level = req['level'] ?? req['Level'];
    final fromGroup =
        await _fetchGroupCourses(req['fromGroup'], major: major, level: level);
    final toGroup =
        await _fetchGroupCourses(req['toGroup'], major: major, level: level);

    // ✅ FIXED: Correctly handle nested "specialRequests" fields
    final special = (req['specialRequests'] ?? req['SpecialRequests'] ?? {}) as Map;
    final partnerSpecial =
        (partner?['specialRequests'] ?? partner?['SpecialRequests'] ?? {}) as Map;

    final haveSections = _extractSections(special['have'] ?? req['have']);
    final wantSections = _extractSections(special['want'] ?? req['want']);
    final deleted = _normalize(req['deletedCourses']);
    final partnerHaveSections =
        _extractSections(partnerSpecial['have'] ?? partner?['have']);

    final fromGroupSections = fromGroup.map((e) => e.section.toLowerCase()).toSet();
    final toGroupSections = toGroup.map((e) => e.section.toLowerCase()).toSet();

    final shared = fromGroupSections.intersection(toGroupSections);
    final intersect = wantSections
        .map((e) => e.toLowerCase())
        .toSet()
        .intersection(partnerHaveSections.map((e) => e.toLowerCase()).toSet());

    final wantCourses = await _fetchSectionCourses(wantSections);
    final partnerHaveCourses = await _fetchSectionCourses(partnerHaveSections);
    final haveCourses = await _fetchSectionCourses(haveSections);
    final deletedSet = deleted.map((e) => e.toLowerCase()).toSet();

    // Addition = toGroup + (myWant ∩ partnerHave) – shared – deleted
    final additions = [
      ...toGroup,
      ...wantCourses.where((c) => intersect.contains(c.section.toLowerCase())),
      ...partnerHaveCourses.where((c) => intersect.contains(c.section.toLowerCase())),
    ]
        .where((c) =>
            !shared.contains(c.section.toLowerCase()) &&
            !deletedSet.contains(c.section.toLowerCase()) &&
            !deletedSet.contains(c.code.toLowerCase()))
        .toList();

    // Deletion = fromGroup + myHave – shared – deleted
    final deletions = [
      ...fromGroup,
      ...haveCourses,
    ]
        .where((c) =>
            !shared.contains(c.section.toLowerCase()) &&
            !deletedSet.contains(c.section.toLowerCase()) &&
            !deletedSet.contains(c.code.toLowerCase()))
        .toList();

    final sharedRows =
        fromGroup.where((c) => shared.contains(c.section.toLowerCase())).toList();
    final before = _sumHours([...deletions, ...sharedRows]);
    final after = _sumHours([...additions, ...sharedRows]);

    return _FormData(
      studentName: req['studentName'] ?? 'Unknown',
      studentId: _extractStudentId(req['studentEmail'] ?? ''),
      studentEmail: req['studentEmail'] ?? '',
      studentMajor: 'Computer and Information Sciences',
      additions: additions,
      deletions: deletions,
      beforeHours: before,
      afterHours: after,
    );
  }

  String _extractStudentId(String email) {
    final m = RegExp(r'\d{9,}').firstMatch(email);
    return m?.group(0) ?? '--';
  }

  void _resetZoom({bool notify = true}) {
    _isUpdatingZoom = true;
    _zoomScale = 1.0;
    _zoomController.value = Matrix4.identity();
    _isUpdatingZoom = false;
    if (notify && mounted) setState(() {});
  }

  void _updateZoom(double delta) {
    final next = (_zoomScale + delta).clamp(_minZoom, _maxZoom);
    if ((next - _zoomScale).abs() < 0.001) return;
    _isUpdatingZoom = true;
    _zoomScale = next;
    final Matrix4 matrix = Matrix4.copy(_zoomController.value);
    matrix.storage[0] = next;
    matrix.storage[5] = next;
    _zoomController.value = matrix;
    _isUpdatingZoom = false;
    setState(() {});
  }

  void _zoomIn() => _updateZoom(0.2);

  void _zoomOut() => _updateZoom(-0.2);

  void _handleZoomControllerChange() {
    if (_isUpdatingZoom) return;
    final controllerScale = _zoomController.value.getMaxScaleOnAxis();
    final clamped = controllerScale.clamp(_minZoom, _maxZoom);
    if ((clamped - _zoomScale).abs() < 0.01) return;
    _isUpdatingZoom = true;
    _zoomScale = clamped;
    if (controllerScale != clamped) {
      _zoomController.value = Matrix4.identity()..scale(clamped);
    }
    _isUpdatingZoom = false;
    setState(() {});
  }

  // ─────────────── Generate PDF ───────────────
  Future<void> _generatePdf() async {
    setState(() => _loading = true);
    try {
      final req = await _fetchSwapRequest(widget.myRequestId);
      if (req == null) throw Exception('Swap request not found');

      Map<String, dynamic>? partner;
      final partnerId = req['partnerRequestId'];
      if (partnerId != null && partnerId.toString().isNotEmpty) {
        partner = await _fetchSwapRequest(partnerId);
      }

      final meForm = await _buildFormData(req, partner);
      final partnerForm = partner != null
          ? await _buildFormData(partner, req)
          : const _FormData(
              studentName: 'Awaiting Partner',
              studentId: '--',
              studentEmail: '',
              studentMajor: '',
              additions: [],
              deletions: [],
              beforeHours: 0,
              afterHours: 0,
            );

      final pdf = await _buildPdf(meForm, partnerForm);
      _resetZoom(notify: false);
      setState(() {
        _pdfBytes = pdf;
      });
    } catch (e, st) {
      debugPrint('❌ PDF generation failed: $e\n$st');
      _errorMessage = e.toString();
    } finally {
      setState(() => _loading = false);
    }
  }

  // ─────────────── PDF Builder (right-side cropping FIXED) ───────────────
  Future<Uint8List> _buildPdf(_FormData me, _FormData partner) async {
    final PdfDocument doc = PdfDocument();

    // Load the form image and compute its intrinsic size so we can scale cleanly.
    final ByteData formData = await rootBundle.load('assets/images/form.png');
    final Uint8List formBytes = formData.buffer.asUint8List();
    final PdfBitmap bg = PdfBitmap(formBytes);

    final ui.Codec codec = await ui.instantiateImageCodec(formBytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image formImage = frame.image;
    final double imageWidth = formImage.width.toDouble();
    final double imageHeight = formImage.height.toDouble();
    formImage.dispose();

    final PdfFont regular = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final PdfBrush brush = PdfSolidBrush(PdfColor(0, 82, 204));

    codec.dispose();

    void drawForm(_FormData form) {
      final page = doc.pages.add();
      final g = page.graphics;
      final ui.Size pageSize = page.getClientSize();

      const double baseWidth = 595.0; // approximate logical width of template
      const double baseHeight = 842.0; // approximate logical height (A4)

      final double scale = math.min(
        pageSize.width / imageWidth,
        pageSize.height / imageHeight,
      );
      final double drawWidth = imageWidth * scale;
      final double drawHeight = imageHeight * scale;
      final double offsetX = (pageSize.width - drawWidth) / 2;
      final double offsetY = (pageSize.height - drawHeight) / 2;

      g.drawImage(
        bg,
        ui.Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight),
      );

      double mapX(double baseX) => offsetX + (baseX / baseWidth) * drawWidth;
      double mapY(double baseY) => offsetY + (baseY / baseHeight) * drawHeight;
      double mapWidth(double width) => (width / baseWidth) * drawWidth;
      double mapHeight(double height) => (height / baseHeight) * drawHeight;

      String sanitize(String value, bool allowBlank) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return allowBlank ? '' : '-';
        return trimmed;
      }

      void drawField(
        String text,
        double baseX,
        double baseY, {
        double width = 120,
        double height = 18,
        PdfFont? font,
        bool allowBlank = false,
        PdfStringFormat? format,
      }) {
        g.drawString(
          sanitize(text, allowBlank),
          font ?? regular,
          brush: brush,
          bounds: ui.Rect.fromLTWH(
            mapX(baseX),
            mapY(baseY),
            mapWidth(width),
            mapHeight(height),
          ),
          format: format,
        );
      }

      // Student info fields (positions measured against the template)
      drawField(form.studentName, 350, 188, width: 210);
      drawField(form.studentId, 110, 188, width: 130);
      drawField(form.studentEmail, 290, 215, width: 220);
      drawField(
        form.studentMajor,
        360,
        236,
        width: 200,
        height: 40,
        format: PdfStringFormat(
          alignment: PdfTextAlignment.left,
          lineAlignment: PdfVerticalAlignment.top,
          wordWrap: PdfWordWrapType.word,
        ),
      );
      drawField('${form.beforeHours}', 240, 240, width: 80);
      drawField('${form.afterHours}', 90, 240, width: 80);

      const double baseRowHeight = 21;
      const double addStartY = 338;
      const double delStartY = 506;

      void drawCourseRows(List<_CourseRow> rows, double startBaseY) {
        double rowBaseY = startBaseY;
        if (rows.isEmpty) {
          drawField('No courses', 150, rowBaseY, width: 260);
          return;
        }

        for (final course in rows.take(5)) {
          final PdfStringFormat centerFormat =
              PdfStringFormat(alignment: PdfTextAlignment.center);

          drawField('${course.hours}', 140, rowBaseY - 4, width: 50, format: centerFormat);
          drawField(course.name, 206, rowBaseY - 1, width: 205);
          drawField(course.section, 430, rowBaseY, width: 45, format: centerFormat);
          drawField(course.code, 456, rowBaseY, width: 122, format: centerFormat);

          rowBaseY += baseRowHeight;
        }
      }

      drawCourseRows(form.additions, addStartY);
      drawCourseRows(form.deletions, delStartY);

      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      drawField(date, 90, 640, width: 120);
      drawField(form.studentName, 360, 640, width: 200);
    }

    drawForm(me);
    drawForm(partner);

    final bytes = await doc.save();
    doc.dispose();
    return Uint8List.fromList(bytes);
  }

  // ─────────────── UI ───────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0097B2),
        foregroundColor: Colors.white,
        title: const Text('Generate PDF'),
        actions: [
          if (_pdfBytes != null) ...[
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: () async {
                await Printing.layoutPdf(onLayout: (_) async => _pdfBytes!);
              },
            ),
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () async {
                await Printing.sharePdf(bytes: _pdfBytes!, filename: 'swap_form.pdf');
              },
            ),
          ],
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0097B2), Color(0xFF0E0259)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: _loading
              ? const CircularProgressIndicator(color: Colors.white)
              : _pdfBytes == null
                  ? Text(_errorMessage ?? 'Tap refresh to generate PDF',
                      style: const TextStyle(color: Colors.white))
                  : Card(
                      margin: const EdgeInsets.all(16),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: InteractiveViewer(
                              transformationController: _zoomController,
                              minScale: _minZoom,
                              maxScale: _maxZoom,
                              boundaryMargin: const EdgeInsets.all(96),
                              clipBehavior: Clip.none,
                              child: PdfPreview(
                                build: (format) async => _pdfBytes!,
                                canChangeOrientation: false,
                                canChangePageFormat: false,
                                allowPrinting: false,
                                allowSharing: false,
                                actions: const [],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(32),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Zoom out',
                                    onPressed:
                                        _zoomScale <= _minZoom ? null : _zoomOut,
                                    icon: const Icon(Icons.remove),
                                    color: Colors.white,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: Text(
                                      '${(_zoomScale * 100).round()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Zoom in',
                                    onPressed:
                                        _zoomScale >= _maxZoom ? null : _zoomIn,
                                    icon: const Icon(Icons.add),
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 1,
                                    height: 24,
                                    color: Colors.white24,
                                  ),
                                  IconButton(
                                    tooltip: 'Reset zoom',
                                    onPressed:
                                        (_zoomScale - 1.0).abs() < 0.01
                                            ? null
                                            : _resetZoom,
                                    icon: const Icon(Icons.refresh),
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}
