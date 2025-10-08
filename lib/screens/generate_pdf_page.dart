import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:printing/printing.dart';

class GeneratePdfPage extends StatefulWidget {
  // You can pass real user data here later if you want
  final String studentName;
  final String fromGroup;
  final String toGroup;

  const GeneratePdfPage({
    super.key,
    this.studentName = "Ali Ahmed",
    this.fromGroup = "2",
    this.toGroup = "3",
  });

  @override
  State<GeneratePdfPage> createState() => _GeneratePdfPageState();
}

class _GeneratePdfPageState extends State<GeneratePdfPage> {
  @override
  void initState() {
    super.initState();
    _generateAndPreviewPdf();
  }

  /// 🔹 Generate the filled PDF and show preview
  Future<void> _generateAndPreviewPdf() async {
    try {
      // 1️⃣ Load the existing PDF template from assets
      final data = await rootBundle.load('assets/images/form.pdf');
      final PdfDocument document =
          PdfDocument(inputBytes: data.buffer.asUint8List());

      // 2️⃣ Get the first page
      final PdfPage page = document.pages[0];

      // 3️⃣ Choose font and style
      final PdfFont font = PdfStandardFont(PdfFontFamily.helvetica, 12);

      // 4️⃣ Write text at specific positions
      // 🟢 You’ll adjust coordinates once you confirm placement
      page.graphics.drawString(
        "Name: ${widget.studentName}",
        font,
        bounds: const Rect.fromLTWH(60, 100, 300, 20),
      );
      page.graphics.drawString(
        "From Group: ${widget.fromGroup}",
        font,
        bounds: const Rect.fromLTWH(60, 130, 300, 20),
      );
      page.graphics.drawString(
        "To Group: ${widget.toGroup}",
        font,
        bounds: const Rect.fromLTWH(60, 160, 300, 20),
      );

      // 5️⃣ Save the edited PDF as bytes
      final Uint8List bytes = Uint8List.fromList(await document.save());
      document.dispose();

      // 6️⃣ Show preview in PDF viewer (printing package)
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      debugPrint("❌ Error generating PDF: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error generating PDF: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(color: Colors.teal),
      ),
    );
  }
}
