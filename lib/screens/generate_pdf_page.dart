import 'dart:typed_data';
import 'dart:ui' show Rect;
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generateAndPreviewPdf();
  }

  T? _pick<T>(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k) && m[k] != null && (m[k] is T)) return m[k] as T;
    }
    return null;
  }

  Future<void> _generateAndPreviewPdf() async {
    try {
      // 1️⃣ Fetch swap request
      final swapRef = FirebaseFirestore.instance
          .collection('swap_requests')
          .doc(widget.myRequestId);
      final swapSnap = await swapRef.get();
      if (!swapSnap.exists) throw Exception("Swap request not found.");
      final swap = (swapSnap.data() ?? {}) as Map<String, dynamic>;

      // 2️⃣ Resolve student ID from swap request
      final resolvedStudentId =
          _pick<String>(swap, ["studentId", "userId", "uid", "studentUID"]);

      // 3️⃣ Fetch user document
      Map<String, dynamic>? userData;
      if (resolvedStudentId != null && resolvedStudentId.isNotEmpty) {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(resolvedStudentId)
            .get();
        if (userSnap.exists) {
          userData = userSnap.data();
        }
      }

      // 4️⃣ Extract data
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

      // ✅ Extract ID from first 9 digits of email
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

      // 5️⃣ Load PDF
      final ByteData pdfData = await rootBundle.load('assets/images/form.pdf');
      final PdfDocument document =
          PdfDocument(inputBytes: pdfData.buffer.asUint8List());
      final PdfPage page = document.pages[0];
      final PdfFont font = PdfStandardFont(PdfFontFamily.helvetica, 12);
      final blueBrush = PdfBrushes.blue;

      // 6️⃣ Fill PDF
      page.graphics.drawString(studentName, font,
          brush: blueBrush, bounds: const Rect.fromLTWH(330, 180, 200, 20));
      page.graphics.drawString(studentId, font,
          brush: blueBrush, bounds: const Rect.fromLTWH(90, 180, 200, 20));
      page.graphics.drawString(studentEmail, font,
          brush: blueBrush, bounds: const Rect.fromLTWH(300, 215, 200, 20));
      page.graphics.drawString(studentPhone, font,
          brush: blueBrush, bounds: const Rect.fromLTWH(90, 215, 200, 20));
      page.graphics.drawString(studentMajor, font,
          brush: blueBrush, bounds: const Rect.fromLTWH(370, 240, 200, 20));

      // Footer
      final today = DateTime.now();
      final formattedDate =
          "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

      page.graphics.drawString(studentName, font,
          brush: blueBrush, bounds: const Rect.fromLTWH(380, 640, 200, 20));
  
      page.graphics.drawString(formattedDate, font,
          brush: blueBrush, bounds: const Rect.fromLTWH(80, 640, 200, 20));

      // Mark Option 2
      final PdfFont xFont =
          PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
      page.graphics.drawString("X", xFont,
          brush: blueBrush, bounds: const Rect.fromLTWH(525, 595, 20, 20));

      // 7️⃣ Show Preview
      final Uint8List pdfBytes = Uint8List.fromList(await document.save());
      document.dispose();

      await Printing.layoutPdf(
        onLayout: (_) async => pdfBytes,
        name: 'Swap_Form_${studentId}.pdf',
      );

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint("❌ Error generating PDF: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error generating PDF: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Generate PDF",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      backgroundColor: Colors.white,
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(color: Colors.teal)
            : const Text(
                "PDF generated successfully!",
                style: TextStyle(fontSize: 16, color: Colors.teal),
              ),
      ),
    );
  }
}
