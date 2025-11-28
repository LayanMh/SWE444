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
  
  // Zoom functionality with specific levels
  TransformationController? _zoomController;
  double _zoomScale = 1.0;
  bool _isUpdatingZoom = false;
  
  // Specific zoom levels: 70%, 80%, 90%, 100%, 110%, 120%
  static const List<double> _zoomLevels = [0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.4, 1.6, 1.7];
  int _currentZoomIndex = 3; // Start at 100% (index 3)
  
  static const double _minZoom = 0.7;
  static const double _maxZoom = 1.7;

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
  
  // Zoom methods with specific levels
  void _resetZoom({bool notify = true}) {
    if (_zoomController == null) return;
    _isUpdatingZoom = true;
    _currentZoomIndex = 3; // Reset to 100%
    _zoomScale = _zoomLevels[_currentZoomIndex];
    _zoomController!.value = Matrix4.identity();
    _isUpdatingZoom = false;
    if (notify && mounted) setState(() {});
  }

  void _zoomIn() {
    if (_currentZoomIndex >= _zoomLevels.length - 1) return;
    _isUpdatingZoom = true;
    _currentZoomIndex++;
    _zoomScale = _zoomLevels[_currentZoomIndex];
    final Matrix4 matrix = Matrix4.copy(_zoomController!.value);
    matrix.storage[0] = _zoomScale;
    matrix.storage[5] = _zoomScale;
    _zoomController!.value = matrix;
    _isUpdatingZoom = false;
    setState(() {});
  }

  void _zoomOut() {
    if (_currentZoomIndex <= 0) return;
    _isUpdatingZoom = true;
    _currentZoomIndex--;
    _zoomScale = _zoomLevels[_currentZoomIndex];
    final Matrix4 matrix = Matrix4.copy(_zoomController!.value);
    matrix.storage[0] = _zoomScale;
    matrix.storage[5] = _zoomScale;
    _zoomController!.value = matrix;
    _isUpdatingZoom = false;
    setState(() {});
  }

  void _handleZoomControllerChange() {
    if (_isUpdatingZoom || _zoomController == null) return;
    final controllerScale = _zoomController!.value.getMaxScaleOnAxis();
    
    // Find closest zoom level
    int closestIndex = 0;
    double minDiff = (controllerScale - _zoomLevels[0]).abs();
    for (int i = 1; i < _zoomLevels.length; i++) {
      double diff = (controllerScale - _zoomLevels[i]).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closestIndex = i;
      }
    }
    
    if (closestIndex != _currentZoomIndex) {
      _isUpdatingZoom = true;
      _currentZoomIndex = closestIndex;
      _zoomScale = _zoomLevels[_currentZoomIndex];
      _zoomController!.value = Matrix4.identity()..scale(_zoomScale);
      _isUpdatingZoom = false;
      setState(() {});
    }
  }

  /// Detect if text contains Arabic characters
  bool _containsArabic(String text) {
    final arabicRegex = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]');
    return arabicRegex.hasMatch(text);
  }

  /// Get text direction based on content
  pw.TextDirection _getTextDirection(String text) {
    return _containsArabic(text) ? pw.TextDirection.rtl : pw.TextDirection.ltr;
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

  /// Generate professional PDF document with Arabic support using Amiri font
  Future<void> _generatePDFDocument() async {
    if (_generatedCV == null) return;

    try {
      final pdf = pw.Document();
      final lines = _generatedCV!.split('\n');
      
      // Debug: Print first 10 lines to see the structure
      debugPrint('📄 CV Content (first 10 lines):');
      for (int i = 0; i < (lines.length > 10 ? 10 : lines.length); i++) {
        debugPrint('Line $i: "${lines[i]}"');
      }
      
      final parsedContent = _parseMarkdownContent(lines);

      // Load Arabic-compatible fonts - Amiri has excellent Arabic support
      final arabicFont = await PdfGoogleFonts.amiriRegular();
      final arabicFontBold = await PdfGoogleFonts.amiriBold();

      // Alternative fonts if Amiri doesn't work:
      // final arabicFont = await PdfGoogleFonts.notoSansArabicRegular();
      // final arabicFontBold = await PdfGoogleFonts.notoSansArabicBold();
      
      // OR
      // final arabicFont = await PdfGoogleFonts.scheherazadeNewRegular();
      // final arabicFontBold = await PdfGoogleFonts.scheherazadeNewBold();

      // Use MultiPage with Arabic font support
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          theme: pw.ThemeData.withFont(
            base: arabicFont,
            bold: arabicFontBold,
          ),
          build: (pw.Context context) => _buildProfessionalPDF(
            parsedContent,
            arabicFont,
            arabicFontBold,
          ),
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

  /// Parse content into structured data with improved name extraction
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

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmedLine = line.trim();
      
      // Skip completely empty lines
      if (trimmedLine.isEmpty) continue;
      
      // Skip separator lines
      if (trimmedLine == '---' || trimmedLine.startsWith('---')) continue;
      
      // Extract name from first few non-empty lines
      if (!nameFound && i < 5) {
        // Remove markdown formatting
        String cleanedLine = trimmedLine
            .replaceAll(RegExp(r'^#+\s*'), '') // Remove # headers
            .replaceAll(RegExp(r'\*+'), '')    // Remove asterisks
            .replaceAll(RegExp(r'^Name:\s*', caseSensitive: false), '') // Remove "Name:" prefix
            .trim();
        
        // Check if this looks like a name (not email, not section header, reasonable length)
        bool looksLikeName = cleanedLine.isNotEmpty &&
                            !cleanedLine.contains('@') &&
                            !cleanedLine.contains(':') &&
                            cleanedLine.length >= 3 &&
                            cleanedLine.length <= 100 &&
                            !cleanedLine.toUpperCase().contains('EMAIL') &&
                            !cleanedLine.toUpperCase().contains('PROFESSIONAL') &&
                            !cleanedLine.toUpperCase().contains('EDUCATION');
        
        // Check word count (1-6 words for name)
        if (looksLikeName) {
          final words = cleanedLine.split(RegExp(r'\s+'));
          if (words.length >= 1 && words.length <= 6) {
            content['name'] = cleanedLine;
            nameFound = true;
            debugPrint('📝 Name extracted at line $i: "$cleanedLine" (${words.length} words)');
            continue;
          }
        }
      }
      
      // Extract email
      if (!emailFound) {
        final emailMatch = RegExp(r'\b[\w\.-]+@[\w\.-]+\.\w+\b').firstMatch(trimmedLine);
        if (emailMatch != null) {
          content['email'] = emailMatch.group(0)!;
          emailFound = true;
          debugPrint('📧 Email extracted: "${content['email']}"');
          continue;
        }
      }
      
      // Check if line is section header
      String cleanHeader = trimmedLine
          .replaceAll(RegExp(r'^#+\s*'), '')
          .replaceAll(RegExp(r'\*+'), '')
          .trim();
      
      bool isAllCapsHeader = cleanHeader.isNotEmpty && 
                           cleanHeader == cleanHeader.toUpperCase() &&
                           !cleanHeader.contains('-') &&
                           !cleanHeader.contains('@') &&
                           !_containsArabic(cleanHeader) &&
                           cleanHeader.split(' ').length <= 5 &&
                           cleanHeader.length > 3;
      
      if (line.startsWith('##') || isAllCapsHeader) {
        // Save previous section
        if (currentSection != null && currentContent.isNotEmpty) {
          content['sections'].add({
            'title': currentSection,
            'content': List<String>.from(currentContent),
          });
          currentContent.clear();
        }
        // Start new section
        currentSection = cleanHeader;
        debugPrint('🔖 Section found: "$currentSection"');
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

    // Debug output
    debugPrint('✅ Final Parsed Name: "${content['name']}"');
    debugPrint('✅ Final Parsed Email: "${content['email']}"');
    debugPrint('✅ Total Sections: ${content['sections'].length}');

    return content;
  }

  /// Build professional PDF with Arabic support and intelligent pagination
  List<pw.Widget> _buildProfessionalPDF(
    Map<String, dynamic> content,
    pw.Font arabicFont,
    pw.Font arabicFontBold,
  ) {
    List<pw.Widget> widgets = [];

    // Header with name (with Arabic support)
    if (content['name'] != null && content['name'].toString().isNotEmpty) {
      final name = content['name'].toString();
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            name,
            style: pw.TextStyle(
              fontSize: 28,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
              font: arabicFontBold,
            ),
            textDirection: _getTextDirection(name),
            textAlign: _containsArabic(name) ? pw.TextAlign.right : pw.TextAlign.center,
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
              font: arabicFont,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ),
      );
      widgets.add(pw.Divider(thickness: 2, color: PdfColors.black));
      widgets.add(pw.SizedBox(height: 15));
    }

    // Sections with smart pagination
    final sections = content['sections'] as List<Map<String, dynamic>>;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      
      // Add spacing before section (except first one)
      if (i > 0) {
        widgets.add(pw.SizedBox(height: 20));
      }
      
      // Build section content entries first
      final sectionContent = section['content'] as List<String>;
      final entries = _buildSectionEntries(sectionContent, arabicFont, arabicFontBold);
      
      if (entries.isEmpty) continue; // Skip empty sections
      
      // Section title
      final sectionTitle = section['title'].toString();
      
      // Wrap section header WITH first entry to keep them together
      widgets.add(
        pw.Wrap(
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Section header
                pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Text(
                    sectionTitle,
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                      font: arabicFontBold,
                    ),
                    textDirection: _getTextDirection(sectionTitle),
                  ),
                ),
                pw.Divider(thickness: 1, color: PdfColors.grey400),
                pw.SizedBox(height: 8),
                
                // First entry (always stays with header)
                entries[0],
              ],
            ),
          ],
        ),
      );
      
      // Add remaining entries (can flow across pages independently)
      for (var j = 1; j < entries.length; j++) {
        widgets.add(entries[j]);
      }
    }

    return widgets;
  }

  /// Build entries with Arabic support
  List<pw.Widget> _buildSectionEntries(
    List<String> sectionContent,
    pw.Font arabicFont,
    pw.Font arabicFontBold,
  ) {
    List<pw.Widget> entries = [];
    List<pw.Widget> currentEntry = [];
    bool isInEntry = false;
    
    for (var line in sectionContent) {
      var cleanLine = line
          .replaceAll('**', '')
          .replaceAll('***', '')
          .replaceAll('###', '')
          .replaceAll('__', '')
          .trim();
      
      if (cleanLine.isEmpty) continue;
      
      // Detect entry start (bold title or ### heading)
      bool isEntryStart = line.startsWith('- **') || 
                         line.startsWith('### ') || 
                         (line.contains('**') && !line.trim().startsWith('- '));
      
      if (isEntryStart) {
        // Save previous entry
        if (currentEntry.isNotEmpty) {
          entries.add(
            pw.Wrap(
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: List.from(currentEntry),
                ),
              ],
            ),
          );
          currentEntry.clear();
        }
        isInEntry = true;
      }
      
      // Add content to current entry with Arabic support
      if (line.startsWith('- **') || line.startsWith('### ') || line.contains('**')) {
        // Entry title
        cleanLine = line
            .replaceAll('### ', '')
            .replaceAll('- **', '')
            .replaceAll('**', '')
            .replaceAll('- ', '')
            .trim();
        
        currentEntry.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
            child: pw.Text(
              cleanLine,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
                font: arabicFontBold,
              ),
              textDirection: _getTextDirection(cleanLine),
            ),
          ),
        );
      } else if (line.trim().startsWith('- ')) {
        // Bullet point
        cleanLine = line.trim().substring(2).replaceAll('**', '').trim();
        currentEntry.add(
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
                    style: pw.TextStyle(
                      fontSize: 10,
                      height: 1.4,
                      color: PdfColors.black,
                      font: arabicFont,
                    ),
                    textDirection: _getTextDirection(cleanLine),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // Regular text
        currentEntry.add(
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
                font: line.toUpperCase() == line && line.length < 50 
                    ? arabicFontBold 
                    : arabicFont,
              ),
              textDirection: _getTextDirection(cleanLine),
            ),
          ),
        );
      }
    }
    
    // Add the last entry
    if (currentEntry.isNotEmpty) {
      entries.add(
        pw.Wrap(
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: List.from(currentEntry),
            ),
          ],
        ),
      );
    }
    
    return entries;
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
        _showSuccessMessage('PDF downloaded successfully! check your Files.');
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
       backgroundColor: Color(0xFF01509B),
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
         gradient: const LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFF01509B),
    Color(0xFF0571C5),
    Color(0xFF83C8EF),
  ],
  stops: [0.0, 0.5, 1.0],
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
                  decoration: const BoxDecoration(
  color: Color(0xFFF5F8FA),
  borderRadius: BorderRadius.only(
    topLeft: Radius.circular(30),
    topRight: Radius.circular(30),
  ),
),
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF01509B),
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
                      child:GestureDetector(
  onTap: _isDownloading ? null : _downloadPDF,
  child: Container(
    height: 50,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          Color(0xFF01509B),
          Color(0xFF83C8EF),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Center(
      child: _isDownloading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.download, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Download PDF',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
    ),
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
                color: const Color(0xFF01509B).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 80,
                color: Color(0xFF01509B),
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
              color: Color(0xFF01509B),
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
              color: Color(0xFF01509B),
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
    color: const Color(0xFF01509B).withOpacity(0.10),
    border: Border(
      bottom: BorderSide(
        color: const Color(0xFF01509B).withOpacity(0.2),
        width: 1,
      ),
    ),
  ),
  child: Row(
    children: [
      const Icon(Icons.check_circle, color: Color(0xFF01509B), size: 20),
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
          foregroundColor: const Color(0xFF01509B),
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
                      // Zoom controls at bottom right with specific percentages
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFF01509B).withOpacity(0.85),
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Zoom out',
                                onPressed: _currentZoomIndex <= 0 ? null : _zoomOut,
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
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Zoom in',
                                onPressed: _currentZoomIndex >= _zoomLevels.length - 1 ? null : _zoomIn,
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
                                onPressed: _currentZoomIndex != 3 ? _resetZoom : null,
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