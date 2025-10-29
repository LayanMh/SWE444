import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:printing/printing.dart';

class GeneratePdfPage extends StatefulWidget {
  final String myRequestId;

  const GeneratePdfPage({super.key, required this.myRequestId});

  @override
  State<GeneratePdfPage> createState() => _GeneratePdfPageState();
}

class _GeneratePdfPageState extends State<GeneratePdfPage> {
  Uint8List? _pdfBytes;

  // 🎨 App palette
  static const Color kTeal = Color(0xFF0097B2);
  static const Color kIndigo = Color(0xFF0E0259);

  @override
  void initState() {
    super.initState();
    _generatePdfBytes();
  }

  T? _pick<T>(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null && (m[k] is T)) return m[k] as T;
    }
    return null;
  }

  PdfColor _pdfColorFrom(Color color) {
    int channel(double component) =>
        (component * 255.0).round().clamp(0, 255);

    return PdfColor(
      channel(color.r),
      channel(color.g),
      channel(color.b),
      channel(color.a),
    );
  }

  Future<void> _generatePdfBytes() async {
    try {
      // 1) Fetch swap request
      final swapSnap = await FirebaseFirestore.instance
          .collection('swap_requests')
          .doc(widget.myRequestId)
          .get();
      if (!swapSnap.exists) {
        throw Exception("Swap request not found.");
      }
      final swap = swapSnap.data() ?? <String, dynamic>{};

      // 2) Resolve user
      final resolvedStudentId =
          _pick<String>(swap, ["studentId", "userId", "uid", "studentUID"]);

      Map<String, dynamic>? userData;
      if (resolvedStudentId != null && resolvedStudentId.isNotEmpty) {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(resolvedStudentId)
            .get();
        if (userSnap.exists) userData = userSnap.data();
      }

      // 3) Extract fields
      final firstName = _pick<String>(userData ?? {}, ["FName"]) ??
          _pick<String>(swap, ["studentFirstName"]);
      final lastName = _pick<String>(userData ?? {}, ["LName"]) ??
          _pick<String>(swap, ["studentLastName"]);
      final studentName =
          "${firstName ?? ''} ${lastName ?? ''}".trim().isNotEmpty
              ? "${firstName ?? ''} ${lastName ?? ''}".trim()
              : (_pick<String>(swap, ["studentName"]) ?? "Student Name");

      final studentEmail = _pick<String>(userData ?? {}, ["email"]) ??
          _pick<String>(swap, ["email", "studentEmail"]) ??
          "student@example.com";

      // Try first 9 digits from email as ID
      final emailIdMatch = RegExp(r'^\d{9}').firstMatch(studentEmail);
      final studentId = emailIdMatch != null
          ? emailIdMatch.group(0)!
          : (resolvedStudentId ?? "000000");

      final studentPhone = _pick<String>(userData ?? {}, ["phone"]) ??
          _pick<String>(swap, ["phone", "studentPhone"]) ??
          "0500000000";
      final studentMajor = _pick<String>(userData ?? {}, ["major"]) ??
          _pick<String>(swap, ["major", "studentMajor"]) ??
          "Computer Science";

      // 4) Load base PDF (from assets)
      final ByteData pdfData = await rootBundle.load('assets/images/form.pdf');
      final PdfDocument document =
          PdfDocument(inputBytes: pdfData.buffer.asUint8List());
      final PdfPage page = document.pages[0];
      final PdfFont font = PdfStandardFont(PdfFontFamily.helvetica, 12);

      // Teal brush to match app
      final PdfBrush tealBrush = PdfSolidBrush(_pdfColorFrom(kTeal));

      // 5) Fill the PDF
      page.graphics.drawString(studentName, font,
          brush: tealBrush, bounds: const Rect.fromLTWH(330, 180, 200, 20));
      page.graphics.drawString(studentId, font,
          brush: tealBrush, bounds: const Rect.fromLTWH(90, 180, 200, 20));
      page.graphics.drawString(studentEmail, font,
          brush: tealBrush, bounds: const Rect.fromLTWH(300, 215, 200, 20));
      page.graphics.drawString(studentPhone, font,
          brush: tealBrush, bounds: const Rect.fromLTWH(90, 215, 200, 20));
      page.graphics.drawString(studentMajor, font,
          brush: tealBrush, bounds: const Rect.fromLTWH(370, 240, 200, 20));

      final today = DateTime.now();
      final formattedDate =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      page.graphics.drawString(studentName, font,
          brush: tealBrush, bounds: const Rect.fromLTWH(380, 640, 200, 20));
      page.graphics.drawString(formattedDate, font,
          brush: tealBrush, bounds: const Rect.fromLTWH(80, 640, 200, 20));

      final PdfFont xFont =
          PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
      page.graphics.drawString("X", xFont,
          brush: tealBrush, bounds: const Rect.fromLTWH(525, 595, 20, 20));

      // 6) Save to memory
      final Uint8List bytes = Uint8List.fromList(await document.save());
      document.dispose();

      if (!mounted) return;
      setState(() => _pdfBytes = bytes);
    } catch (e) {
      debugPrint("❌ Error generating PDF: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error generating PDF: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canShare = _pdfBytes != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kIndigo,
        elevation: 3,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Generate PDF",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (canShare)
            IconButton(
              tooltip: 'Share PDF',
              icon: const Icon(Icons.share, color: Colors.white),
              onPressed: () async {
                await Printing.sharePdf(
                  bytes: _pdfBytes!,
                  filename: 'Swap_Form.pdf',
                );
              },
            ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: const [kTeal, kIndigo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: _pdfBytes == null
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Card(
                margin: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: PdfPreview(
                    // Keep PdfPreview API minimal for broad compatibility
                    build: (format) async => _pdfBytes!,
                    pdfPreviewPageDecoration:
                        const BoxDecoration(color: Colors.white),
                  ),
                ),
              ),
      ),
    );
  }
}
