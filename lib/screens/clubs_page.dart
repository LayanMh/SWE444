import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class ClubFormPage extends StatefulWidget {
  final Map<String, dynamic>? existingItem;
  final int? itemIndex;

  const ClubFormPage({super.key, this.existingItem, this.itemIndex});

  @override
  State<ClubFormPage> createState() => _ClubFormPageState();
}

class _ClubFormPageState extends State<ClubFormPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  late TextEditingController _titleController;
  late TextEditingController _organizationController;
  late TextEditingController _roleController;
  late TextEditingController _hoursController;
  late TextEditingController _descriptionController;

  File? _certificateFile;
  String? _existingCertificateUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingItem?['title'] ?? '');
    _organizationController = TextEditingController(text: widget.existingItem?['organization'] ?? '');
    _roleController = TextEditingController(text: widget.existingItem?['role'] ?? '');
    _hoursController = TextEditingController(text: widget.existingItem?['hours']?.toString() ?? '');
    _descriptionController = TextEditingController(text: widget.existingItem?['description'] ?? '');
    _existingCertificateUrl = widget.existingItem?['certificateUrl'];

    // Add listeners to trigger rebuild for character counter
    _titleController.addListener(() => setState(() {}));
    _organizationController.addListener(() => setState(() {}));
    _roleController.addListener(() => setState(() {}));
    _descriptionController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _organizationController.dispose();
    _roleController.dispose();
    _hoursController.dispose();
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

  // Validation: Title (Club Name)
  String? _validateTitle(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter a club name';
    }

    final trimmedValue = value.trim();

    if (trimmedValue.length > 30) {
      return 'Club name must be 30 characters or less';
    }

    if (RegExp(r'^[0-9]+$').hasMatch(trimmedValue)) {
      return 'Club name cannot contain only numbers';
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

  // Validation: Role
  String? _validateRole(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your role';
    }

    final trimmedValue = value.trim();

    if (trimmedValue.length > 30) {
      return 'Role must be 30 characters or less';
    }

    if (RegExp(r'^[0-9]+$').hasMatch(trimmedValue)) {
      return 'Role cannot contain only numbers';
    }

    return null;
  }

  // Validation: Hours
  String? _validateHours(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Hours is optional
    }

    final trimmedValue = value.trim();
    final hours = int.tryParse(trimmedValue);

    if (hours == null) {
      return 'Please enter a valid number';
    }

    if (hours < 0) {
      return 'Hours cannot be negative';
    }

    if (hours > 10000) {
      return 'Hours must be less than 10,000';
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
      final String fileName = 'clubs/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
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

  Future<void> _saveClub() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final docId = await _getUserDocId();
      if (docId == null) {
        _showErrorMessage('Unable to identify user');
        return;
      }

      String? certificateUrl = await _uploadCertificate(docId);

      final clubItem = {
        'title': _titleController.text.trim(),
        'organization': _organizationController.text.trim().isEmpty ? null : _organizationController.text.trim(),
        'role': _roleController.text.trim(),
        'hours': _hoursController.text.trim().isEmpty ? null : int.tryParse(_hoursController.text.trim()),
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'certificateUrl': certificateUrl,
      };

      final doc = await _firestore.collection('users').doc(docId).get();
      List<dynamic> items = doc.data()?['clubs'] ?? [];

      if (widget.existingItem != null && widget.itemIndex != null) {
        if (widget.itemIndex! < 0 || widget.itemIndex! >= items.length) {
          _showErrorMessage('Invalid club index');
          return;
        }
        items[widget.itemIndex!] = clubItem;
      } else {
        items.add(clubItem);
      }

      await _firestore.collection('users').doc(docId).update({
        'clubs': items,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving club: $e');

      if (e is FirebaseException) {
        switch (e.code) {
          case 'permission-denied':
            _showErrorMessage('You do not have permission to save this club');
            break;
          case 'unavailable':
            _showErrorMessage('Network error. Please check your connection');
            break;
          case 'not-found':
            _showErrorMessage('User document not found');
            break;
          default:
            _showErrorMessage('Failed to save club: ${e.message}');
        }
      } else {
        _showErrorMessage('Failed to save club');
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
                        widget.existingItem != null ? 'Edit Club' : 'Add Club',
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
                              label: 'Club Name *',
                              hint: 'e.g., Robotics Club',
                              maxLength: 30,
                              validator: _validateTitle,
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextFieldWithCounter(
                              controller: _organizationController,
                              label: 'Organization',
                              hint: 'e.g., University Engineering Department',
                              maxLength: 40,
                              validator: _validateOrganization,
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextFieldWithCounter(
                              controller: _roleController,
                              label: 'Role *',
                              hint: 'e.g., President, Member, Volunteer',
                              maxLength: 30,
                              validator: _validateRole,
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _hoursController,
                              label: 'Participation Hours',
                              hint: 'e.g., 50',
                              keyboardType: TextInputType.number,
                              validator: _validateHours,
                            ),
                            const SizedBox(height: 16.0),
                            _buildCertificatePicker(),
                            const SizedBox(height: 16.0),
                            _buildTextFieldWithWordCounter(
                              controller: _descriptionController,
                              label: 'Description',
                              hint: 'Describe your activities and contributions...',
                              maxLines: 5,
                              minWords: 20,
                              maxLength: 600,
                              validator: _validateDescription,
                            ),
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
      hintStyle: TextStyle(color: Colors.grey[600]),
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
        onPressed: _isSaving ? null : _saveClub,
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