import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class WorkshopFormPage extends StatefulWidget {
  final Map<String, dynamic>? existingItem;
  final int? itemIndex;

  const WorkshopFormPage({super.key, this.existingItem, this.itemIndex});

  @override
  State<WorkshopFormPage> createState() => _WorkshopFormPageState();
}

class _WorkshopFormPageState extends State<WorkshopFormPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  late TextEditingController _titleController;
  late TextEditingController _organizationController;
  late TextEditingController _yearController;
  late TextEditingController _descriptionController;

  File? _certificateFile;
  String? _existingCertificateUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingItem?['title'] ?? '');
    _organizationController = TextEditingController(text: widget.existingItem?['organization'] ?? '');
    _yearController = TextEditingController(text: widget.existingItem?['year']?.toString() ?? '');
    _descriptionController = TextEditingController(text: widget.existingItem?['description'] ?? '');
    _existingCertificateUrl = widget.existingItem?['certificateUrl'];

    // Add listeners to trigger rebuild for character counter
    _titleController.addListener(() => setState(() {}));
    _organizationController.addListener(() => setState(() {}));
    _descriptionController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _organizationController.dispose();
    _yearController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<String?> _getUserDocId() async {
    final prefs = await SharedPreferences.getInstance();
    final microsoftDocId = prefs.getString('microsoft_user_doc_id');

    if (microsoftDocId != null) {
      return microsoftDocId;
    } else if (_auth.currentUser != null) {
      return _auth.currentUser!.uid;
    }
    return null;
  }

  // Validation: Title
  String? _validateTitle(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter a workshop title';
    }

    final trimmedValue = value.trim();

    if (trimmedValue.length > 30) {
      return 'Title must be 30 characters or less';
    }

    if (RegExp(r'^[0-9]+$').hasMatch(trimmedValue)) {
      return 'Title cannot contain only numbers';
    }

    return null;
  }

  // Validation: Organization
  String? _validateOrganization(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final trimmedValue = value.trim();

    if (trimmedValue.length > 40) {
      return 'Organization name must be 40 characters or less';
    }

    if (RegExp(r'^[0-9]+$').hasMatch(trimmedValue)) {
      return 'Organization name cannot contain only numbers';
    }

    return null;
  }

  // Validation: Year
  String? _validateYear(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter a year';
    }

    final trimmedValue = value.trim();
    final year = int.tryParse(trimmedValue);

    if (year == null) {
      return 'Please enter a valid year';
    }

    final currentYear = DateTime.now().year;

    if (year < 2000) {
      return 'Year must be 2000 or later';
    }

    if (year > currentYear) {
      return 'Year cannot be in the future';
    }

    return null;
  }

  // Validation: Description
  String? _validateDescription(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Description is optional
    }

    final trimmedValue = value.trim();
    final wordCount = trimmedValue.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;

    if (wordCount < 20) {
      return 'Description must be at least 20 words';
    }

    if (trimmedValue.length > 600) {
      return 'Description must be 600 characters or less';
    }

    if (RegExp(r'^[0-9]+$').hasMatch(trimmedValue)) {
      return 'Description cannot contain only numbers';
    }

    return null;
  }

  Future<void> _pickCertificate() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() {
          _certificateFile = File(image.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      _showErrorMessage('Failed to pick image');
    }
  }

  Future<String?> _uploadCertificate(String userId) async {
    if (_certificateFile == null) return _existingCertificateUrl;

    try {
      final String fileName = 'workshops/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference ref = _storage.ref().child(fileName);
      
      final UploadTask uploadTask = ref.putFile(_certificateFile!);
      final TaskSnapshot snapshot = await uploadTask;
      
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error uploading certificate: $e');
      
      if (e is FirebaseException) {
        switch (e.code) {
          case 'unauthorized':
            _showErrorMessage('You do not have permission to upload files');
            break;
          case 'canceled':
            _showErrorMessage('Upload was canceled');
            break;
          case 'unknown':
            _showErrorMessage('An unknown error occurred during upload');
            break;
          default:
            _showErrorMessage('Failed to upload certificate: ${e.message}');
        }
      } else {
        _showErrorMessage('Failed to upload certificate');
      }
      return null;
    }
  }

  Future<void> _saveWorkshop() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final docId = await _getUserDocId();
      if (docId == null) {
        _showErrorMessage('Unable to identify user');
        return;
      }

      String? certificateUrl = await _uploadCertificate(docId);

      final workshopItem = {
        'title': _titleController.text.trim(),
        'organization': _organizationController.text.trim(),
        'year': int.tryParse(_yearController.text.trim()),
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'certificateUrl': certificateUrl,
      };

      final doc = await _firestore.collection('users').doc(docId).get();
      List<dynamic> items = doc.data()?['workshops'] ?? [];

      if (widget.existingItem != null && widget.itemIndex != null) {
        if (widget.itemIndex! < 0 || widget.itemIndex! >= items.length) {
          _showErrorMessage('Invalid workshop index');
          return;
        }
        items[widget.itemIndex!] = workshopItem;
      } else {
        items.add(workshopItem);
      }

      await _firestore.collection('users').doc(docId).update({
        'workshops': items,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving workshop: $e');

      if (e is FirebaseException) {
        switch (e.code) {
          case 'permission-denied':
            _showErrorMessage('You do not have permission to save this workshop');
            break;
          case 'unavailable':
            _showErrorMessage('Network error. Please check your connection');
            break;
          case 'not-found':
            _showErrorMessage('User document not found');
            break;
          default:
            _showErrorMessage('Failed to save workshop: ${e.message}');
        }
      } else {
        _showErrorMessage('Failed to save workshop');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.existingItem != null ? 'Edit Workshop' : 'Add Workshop',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTextFieldWithCounter(
                              controller: _titleController,
                              label: 'Workshop Title *',
                              hint: 'e.g., Machine Learning Workshop',
                              maxLength: 30,
                              validator: _validateTitle,
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextFieldWithCounter(
                              controller: _organizationController,
                              label: 'Organization',
                              hint: 'e.g., IEEE Student Branch',
                              maxLength: 40,
                              validator: _validateOrganization,
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _yearController,
                              label: 'Year *',
                              hint: 'e.g., 2024',
                              validator: _validateYear,
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextFieldWithWordCounter(
                              controller: _descriptionController,
                              label: 'Description',
                              hint: 'What did you learn?',
                              maxLines: 5,
                              minWords: 20,
                              maxLength: 600,
                              validator: _validateDescription,
                            ),
                            const SizedBox(height: 16.0),
                            _buildCertificatePicker(),
                            const SizedBox(height: 24.0),
                            _buildSaveButton(),
                          ],
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

  Widget _buildCertificatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Certificate',
          style: TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0e0259),
          ),
        ),
        const SizedBox(height: 8.0),
        InkWell(
          onTap: _pickCertificate,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.upload_file, color: Color(0xFF0097b2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _certificateFile != null
                        ? 'Certificate selected'
                        : _existingCertificateUrl != null
                            ? 'Certificate uploaded (tap to change)'
                            : 'Tap to upload certificate',
                    style: TextStyle(
                      color: _certificateFile != null || _existingCertificateUrl != null
                          ? const Color(0xFF0097b2)
                          : Colors.grey[600],
                    ),
                  ),
                ),
                if (_certificateFile != null || _existingCertificateUrl != null)
                  Icon(Icons.check_circle, color: Colors.green[600]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextFieldWithCounter({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    required int maxLength,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    final currentLength = controller.text.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0e0259),
              ),
            ),
            Text(
              '$currentLength/$maxLength',
              style: TextStyle(
                fontSize: 12.0,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          keyboardType: keyboardType,
          autovalidateMode: AutovalidateMode.disabled,
          inputFormatters: [
            LengthLimitingTextInputFormatter(maxLength),
          ],
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  Widget _buildTextFieldWithWordCounter({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    required int minWords,
    required int maxLength,
    String? Function(String?)? validator,
  }) {
    final currentLength = controller.text.length;
    final wordCount = controller.text.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0e0259),
              ),
            ),
            Text(
              '$wordCount/$minWords words • $currentLength/$maxLength chars',
              style: TextStyle(
                fontSize: 12.0,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          autovalidateMode: AutovalidateMode.disabled,
          inputFormatters: [
            LengthLimitingTextInputFormatter(maxLength),
          ],
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0e0259),
          ),
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          keyboardType: keyboardType,
          autovalidateMode: AutovalidateMode.disabled,
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400]),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0097b2), Color(0xFF006B7A)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0097b2).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveWorkshop,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Save',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }
}