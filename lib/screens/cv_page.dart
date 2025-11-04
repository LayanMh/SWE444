import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../services/cv_generator_service.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';

class CVPage extends StatefulWidget {
  final bool autoGenerate;

  const CVPage({super.key, this.autoGenerate = false});

  @override
  State<CVPage> createState() => _CVPageState();
}

class _CVPageState extends State<CVPage> {
  final CVGeneratorService _cvService = CVGeneratorService();
  bool _isLoading = false;
  bool _isGenerating = false;
  bool _isDownloading = false;
  String? _generatedCV;
  pw.Document? _pdfDocument;
  String? _errorMessage;
  
  // Zoom functionality - made nullable to avoid late initialization error
  TransformationController? _zoomController;
  double _zoomScale = 1.0;
  bool _isUpdatingZoom = false;
  
  static const double _minZoom = 0.8;
  static const double _maxZoom = 2.5;

  @override
  void initState() {
    super.initState();
    _zoomController = TransformationController();
    _zoomController!.addListener(_handleZoomControllerChange);
    _resetZoom(notify: false);
    _loadSavedCV();
    if (widget.autoGenerate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_generatedCV == null && !_isGenerating) {
          _generateCV();
        }
      });
    }
  }

  @override
  void dispose() {
    _zoomController?.removeListener(_handleZoomControllerChange);
    _zoomController?.dispose();
    super.dispose();
  }
  
  // Zoom methods
  void _resetZoom({bool notify = true}) {
    if (_zoomController == null) return;
    _isUpdatingZoom = true;
    _zoomScale = 1.0;
    _zoomController!.value = Matrix4.identity();
    _isUpdatingZoom = false;
    if (notify && mounted) setState(() {});
  }

  void _updateZoom(double delta) {
    if (_zoomController == null) return;
    final next = (_zoomScale + delta).clamp(_minZoom, _maxZoom);
    if ((next - _zoomScale).abs() < 0.001) return;
    _isUpdatingZoom = true;
    _zoomScale = next;
    final Matrix4 matrix = Matrix4.copy(_zoomController!.value);
    matrix.storage[0] = next;
    matrix.storage[5] = next;
    _zoomController!.value = matrix;
    _isUpdatingZoom = false;
    setState(() {});
  }

  void _zoomIn() => _updateZoom(0.2);

  void _zoomOut() => _updateZoom(-0.2);

  void _handleZoomControllerChange() {
    if (_isUpdatingZoom || _zoomController == null) return;
    final controllerScale = _zoomController!.value.getMaxScaleOnAxis();
    final clamped = controllerScale.clamp(_minZoom, _maxZoom);
    if ((clamped - _zoomScale).abs() < 0.01) return;
    _isUpdatingZoom = true;
    _zoomScale = clamped;
    if (controllerScale != clamped) {
      _zoomController!.value = Matrix4.identity()..scale(clamped);
    }
    _isUpdatingZoom = false;
    setState(() {});
  }

  /// Load previously saved CV
  Future<void> _loadSavedCV() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final savedCV = await _cvService.getSavedCV();
      if (mounted && savedCV != null) {
        setState(() {
          _generatedCV = savedCV;
        });
        await _generatePDFDocument();
        if (mounted) {
          setState(() => _isLoading = false);
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load saved CV';
          _isLoading = false;
        });
      }
    }
  }

  /// Generate new CV with AI and create PDF
  Future<void> _generateCV() async {
    if (!mounted) return;
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _pdfDocument = null;
    });

    try {
      final allData = await _cvService.fetchAllUserData();
      final experience = allData['experience'] as Map<String, dynamic>;

      if (!_cvService.hasMinimumData(experience)) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Please add at least one project, workshop, club, or volunteering experience';
            _isGenerating = false;
          });
          _showErrorMessage(_errorMessage!);
        }
        return;
      }

      final cvContent = await _cvService.generateCV();

      if (mounted) {
        setState(() {
          _generatedCV = cvContent;
        });

        await _generatePDFDocument();

        if (mounted) {
          setState(() {
            _isGenerating = false;
          });
          _showSuccessMessage('CV and PDF generated successfully!');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to generate CV: ${e.toString()}';
          _isGenerating = false;
        });
        _showErrorMessage(_errorMessage!);
      }
    }
  }

  /// Generate professional PDF document
  Future<void> _generatePDFDocument() async {
    if (_generatedCV == null) return;

    try {
      final pdf = pw.Document();
      final lines = _generatedCV!.split('\n');
      final parsedContent = _parseMarkdownContent(lines);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) => _buildProfessionalPDF(parsedContent),
        ),
      );

      if (mounted) {
        setState(() {
          _pdfDocument = pdf;
        });
      }
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      _showErrorMessage('Failed to generate PDF: ${e.toString()}');
    }
  }

  /// Parse content into structured data
  Map<String, dynamic> _parseMarkdownContent(List<String> lines) {
    Map<String, dynamic> content = {
      'name': '',
      'email': '',
      'sections': <Map<String, dynamic>>[],
    };

    String? currentSection;
    List<String> currentContent = [];
    bool nameFound = false;
    bool emailFound = false;

    for (var line in lines) {
      final trimmedLine = line.trim();
      
      // Skip completely empty lines
      if (trimmedLine.isEmpty) {
        continue;
      }
      
      // Skip separator lines
      if (trimmedLine == '---' || trimmedLine.startsWith('---')) {
        continue;
      }
      
      // Extract name (should be first line or marked with # or Name:)
      if (!nameFound) {
        if (line.startsWith('# ')) {
          content['name'] = line.substring(2).trim();
          nameFound = true;
          continue;
        } else if (trimmedLine.toLowerCase().contains('name:')) {
          final nameMatch = RegExp(r'(?:name:?\s*)(.+)', caseSensitive: false).firstMatch(trimmedLine);
          if (nameMatch != null) {
            content['name'] = nameMatch.group(1)?.trim() ?? '';
            nameFound = true;
            continue;
          }
        } else if (!trimmedLine.contains(':') && !trimmedLine.toUpperCase().contains('EMAIL') && 
                   trimmedLine.split(' ').length >= 2 && trimmedLine.split(' ').length <= 5) {
          // Likely the name if it's 2-5 words at the start
          content['name'] = trimmedLine;
          nameFound = true;
          continue;
        }
      }
      
      // Extract email
      if (!emailFound && trimmedLine.toLowerCase().contains('email')) {
        final emailMatch = RegExp(r'\b[\w\.-]+@[\w\.-]+\.\w+\b').firstMatch(trimmedLine);
        if (emailMatch != null) {
          content['email'] = emailMatch.group(0) ?? '';
          emailFound = true;
          continue;
        }
      } else if (!emailFound) {
        // Try to find email without "Email:" prefix
        final emailMatch = RegExp(r'\b[\w\.-]+@[\w\.-]+\.\w+\b').firstMatch(trimmedLine);
        if (emailMatch != null && emailMatch.group(0) == trimmedLine) {
          content['email'] = trimmedLine;
          emailFound = true;
          continue;
        }
      }
      
      // Check if line is section header (ALL CAPS or starts with ##)
      bool isAllCapsHeader = trimmedLine.isNotEmpty && 
                           trimmedLine == trimmedLine.toUpperCase() &&
                           !trimmedLine.contains('-') &&
                           !trimmedLine.contains('@') &&
                           trimmedLine.split(' ').length <= 5 &&
                           trimmedLine.length > 3;
      
      if (line.startsWith('## ') || isAllCapsHeader) {
        // Save previous section
        if (currentSection != null && currentContent.isNotEmpty) {
          content['sections'].add({
            'title': currentSection,
            'content': List<String>.from(currentContent),
          });
          currentContent.clear();
        }
        // Start new section
        currentSection = line.startsWith('## ') 
            ? line.substring(3).trim() 
            : trimmedLine;
      } else if (currentSection != null) {
        // Add content to current section
        currentContent.add(trimmedLine);
      }
    }

    // Add the last section
    if (currentSection != null && currentContent.isNotEmpty) {
      content['sections'].add({
        'title': currentSection,
        'content': List<String>.from(currentContent),
      });
    }

    return content;
  }

  /// Build professional PDF with BLACK text
  List<pw.Widget> _buildProfessionalPDF(Map<String, dynamic> content) {
    List<pw.Widget> widgets = [];

    // Header with name
    if (content['name'] != null && content['name'].toString().isNotEmpty) {
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            content['name'],
            style: pw.TextStyle(
              fontSize: 28,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ),
      );
    }

    // Email
    if (content['email'] != null && content['email'].toString().isNotEmpty) {
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 20),
          child: pw.Text(
            'Email: ${content['email']}',
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColors.black,
            ),
          ),
        ),
      );
      widgets.add(pw.Divider(thickness: 2, color: PdfColors.black));
      widgets.add(pw.SizedBox(height: 15));
    }

    // Sections
    final sections = content['sections'] as List<Map<String, dynamic>>;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      
      // Section title
      widgets.add(
        pw.Container(
          margin: pw.EdgeInsets.only(bottom: 8, top: i > 0 ? 15 : 0),
          child: pw.Text(
            section['title'],
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ),
      );

      widgets.add(pw.Divider(thickness: 1, color: PdfColors.grey400));
      widgets.add(pw.SizedBox(height: 8));

      // Section content
      final sectionContent = section['content'] as List<String>;
      for (var line in sectionContent) {
        // Clean up any markdown symbols that might slip through
        var cleanLine = line
            .replaceAll('**', '')  // Remove bold markers
            .replaceAll('***', '') // Remove bold+italic markers
            .replaceAll('###', '') // Remove heading markers
            .replaceAll('__', '')  // Remove underline markers
            .trim();
        
        if (cleanLine.isEmpty) continue;
        
        if (line.startsWith('- **') || line.startsWith('### ') || line.contains('**')) {
          // This is likely a title/heading (strip all formatting)
          cleanLine = line
              .replaceAll('### ', '')
              .replaceAll('- **', '')
              .replaceAll('**', '')
              .replaceAll('- ', '')
              .trim();
          
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
              child: pw.Text(
                cleanLine,
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ),
          );
        } else if (line.trim().startsWith('- ')) {
          // Bullet point
          cleanLine = line.trim().substring(2).replaceAll('**', '').trim();
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(left: 15, bottom: 3),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 4,
                    height: 4,
                    margin: const pw.EdgeInsets.only(top: 4, right: 8),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.black,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      cleanLine,
                      style: const pw.TextStyle(
                        fontSize: 10,
                        height: 1.4,
                        color: PdfColors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          // Regular text (strip any remaining formatting)
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                cleanLine,
                style: pw.TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: PdfColors.black,
                  fontWeight: line.toUpperCase() == line && line.length < 50 
                      ? pw.FontWeight.bold 
                      : pw.FontWeight.normal,
                ),
              ),
            ),
          );
        }
      }
    }

    return widgets;
  }

  /// Download PDF directly to Downloads folder
  Future<void> _downloadPDF() async {
    if (_pdfDocument == null) {
      _showErrorMessage('No PDF available. Please generate CV first.');
      return;
    }

    if (!mounted) return;
    setState(() => _isDownloading = true);

    try {
      // Get Downloads directory path
      Directory? downloadsDir;
      
      if (Platform.isAndroid) {
        // Try to get the public Downloads directory
        downloadsDir = Directory('/storage/emulated/0/Download');
        
        // If Downloads doesn't exist, fall back to external storage
        if (!await downloadsDir.exists()) {
          final externalDir = await getExternalStorageDirectory();
          downloadsDir = Directory('${externalDir?.path}/Download');
          
          // Create Download folder if it doesn't exist
          if (!await downloadsDir.exists()) {
            await downloadsDir.create(recursive: true);
          }
        }
      } else if (Platform.isIOS) {
        // For iOS, use app documents directory
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) {
        throw Exception('Could not access downloads directory');
      }

      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'My_CV_$timestamp.pdf';
      final filePath = '${downloadsDir.path}/$fileName';

      // Save PDF
      final file = File(filePath);
      await file.writeAsBytes(await _pdfDocument!.save());

      if (mounted) {
        setState(() => _isDownloading = false);
        _showSuccessMessage('PDF downloaded successfully!\nSaved to: ${downloadsDir.path}');
      }

      debugPrint('✅ PDF saved to: $filePath');
    } catch (e) {
      debugPrint('❌ Error downloading PDF: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        _showErrorMessage('Failed to download PDF: ${e.toString()}');
      }
    }
  }

  /// Share PDF
  Future<void> _sharePDF() async {
    if (_pdfDocument == null) {
      _showErrorMessage('No PDF available. Please generate CV first.');
      return;
    }

    try {
      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'My_CV_$timestamp.pdf';
      final filePath = '${tempDir.path}/$fileName';

      // Save PDF to temp file
      final file = File(filePath);
      await file.writeAsBytes(await _pdfDocument!.save());

      // Share the file
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'My CV',
        text: 'Here is my professional CV',
      );

      debugPrint('✅ PDF shared: $filePath');
    } catch (e) {
      debugPrint('❌ Error sharing PDF: $e');
      _showErrorMessage('Failed to share PDF: ${e.toString()}');
    }
  }

  /// Print PDF
  Future<void> _printPDF() async {
    if (_pdfDocument == null) {
      _showErrorMessage('No PDF available. Please generate CV first.');
      return;
    }

    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => _pdfDocument!.save(),
        name: 'My_CV.pdf',
      );
    } catch (e) {
      debugPrint('❌ Error printing PDF: $e');
      _showErrorMessage('Failed to print PDF: ${e.toString()}');
    }
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF4ECDC4),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF006B7A), Color(0xFF0097b2), Color(0xFF0e0259)],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header with Print and Share icons only
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'My CV',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    // Print button
                    if (_pdfDocument != null)
                      IconButton(
                        icon: const Icon(Icons.print, color: Colors.white),
                        onPressed: _printPDF,
                        tooltip: 'Print',
                      ),
                    // Share button
                    if (_pdfDocument != null)
                      IconButton(
                        icon: const Icon(Icons.share, color: Colors.white),
                        onPressed: _sharePDF,
                        tooltip: 'Share',
                      ),
                    if (_pdfDocument == null)
                      const SizedBox(width: 96), // Space when buttons not shown
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF0097b2),
                          ),
                        )
                      : _pdfDocument == null
                          ? _buildEmptyState()
                          : _buildPDFPreview(),
                ),
              ),
              
              // Download PDF button at bottom
              if (_pdfDocument != null)
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        spreadRadius: 1,
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isDownloading ? null : _downloadPDF,
                        icon: _isDownloading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download, color: Colors.white),
                        label: Text(
                          _isDownloading ? 'Downloading...' : 'Download PDF',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0097b2),
                          disabledBackgroundColor: Colors.grey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF0097b2).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 80,
                color: Color(0xFF0097b2),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Generating Your CV...',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'AI is creating a professional CV based on your profile',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(
              color: Color(0xFF0097b2),
            ),
            const SizedBox(height: 16),
            
          ],
        ),
      ),
    );
  }

  Widget _buildPDFPreview() {
    if (_isGenerating) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: Color(0xFF0097b2),
              strokeWidth: 3,
            ),
            const SizedBox(height: 24),
            Text(
              'Generating Your CV...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'AI is crafting your professional CV and PDF',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Info banner with regenerate button
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF4ECDC4).withOpacity(0.15),
            border: Border(
              bottom: BorderSide(
                color: const Color(0xFF4ECDC4).withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF4ECDC4), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'CV and PDF ready for download',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _generateCV,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Regenerate'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0097b2),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        
        // PDF Preview with zoom controls
        Expanded(
          child: Container(
            color: Colors.grey[300],
            child: _zoomController == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      // PDF Preview wrapped in InteractiveViewer
                      Positioned.fill(
                        child: InteractiveViewer(
                          transformationController: _zoomController!,
                          minScale: _minZoom,
                          maxScale: _maxZoom,
                          boundaryMargin: const EdgeInsets.all(96),
                          clipBehavior: Clip.none,
                          child: PdfPreview(
                            build: (format) => _pdfDocument!.save(),
                            allowSharing: false,
                            allowPrinting: false,
                            canChangePageFormat: false,
                            canChangeOrientation: false,
                            canDebug: false,
                            pdfFileName: 'My_CV.pdf',
                            previewPageMargin: const EdgeInsets.all(16),
                            scrollViewDecoration: BoxDecoration(
                              color: Colors.grey[300],
                            ),
                            useActions: false,
                            maxPageWidth: 700,
                            actions: const [],
                          ),
                        ),
                      ),
                      // Zoom controls at bottom right
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
                                onPressed: _zoomScale <= _minZoom ? null : _zoomOut,
                                icon: const Icon(Icons.remove),
                                color: Colors.white,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                onPressed: _zoomScale >= _maxZoom ? null : _zoomIn,
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
                                onPressed: (_zoomScale - 1.0).abs() < 0.01 ? null : _resetZoom,
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
      ],
    );
  }
}