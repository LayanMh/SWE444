import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

String? _validateSpecialCharacters(String? value, String fieldName) {
  if (value == null || value.trim().isEmpty) return null;
  final trimmedValue = value.trim();
  
  final specialCharRegex = RegExp(r'[!@#$%^&*()_+=\[\]{};:"\\|,.<>?/~`]');
  if (specialCharRegex.hasMatch(trimmedValue)) {
    return '$fieldName cannot contain special characters';
  }
  return null;
}

class NoEmojiInputFormatter extends TextInputFormatter {
  final RegExp _emojiRegex = RegExp(
    r'[\u{1F600}-\u{1F64F}' // Emoticons
    r'\u{1F300}-\u{1F5FF}' // Symbols & pictographs
    r'\u{1F680}-\u{1F6FF}' // Transport & map symbols
    r'\u{1F1E0}-\u{1F1FF}' // Flags
    r'\u{2600}-\u{26FF}'   // Misc symbols
    r'\u{2700}-\u{27BF}]', // Dingbats
    unicode: true,
  );

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (_emojiRegex.hasMatch(newValue.text)) {
      return oldValue; // ❌ block emojis
    }
    return newValue;
  }
}

class VolunteeringFormPage extends StatefulWidget {
  final Map<String, dynamic>? existingItem;
  final int? itemIndex;

  const VolunteeringFormPage({super.key, this.existingItem, this.itemIndex});

  @override
  State<VolunteeringFormPage> createState() => _VolunteeringFormPageState();
}

class _VolunteeringFormPageState extends State<VolunteeringFormPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  late TextEditingController _titleController;
  late TextEditingController _organizationController;
  late TextEditingController _hoursController;
  late TextEditingController _descriptionController;

  File? _certificateFile;
  String? _existingCertificateUrl;
  bool _isSaving = false;
  String? _certificateError;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingItem?['title'] ?? '');
    _organizationController = TextEditingController(text: widget.existingItem?['organization'] ?? '');
    _hoursController = TextEditingController(text: widget.existingItem?['hours']?.toString() ?? '');
    _descriptionController = TextEditingController(text: widget.existingItem?['description'] ?? '');
    _existingCertificateUrl = widget.existingItem?['certificateUrl'];

    _titleController.addListener(() => setState(() {}));
    _organizationController.addListener(() => setState(() {}));
    _descriptionController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _organizationController.dispose();
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

  String? _validateTitle(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter a title';
    }
    final trimmedValue = value.trim();
    if (trimmedValue.length > 40) {
      return 'Title must be 40 characters or less';
    }
    if (RegExp(r'^[0-9]+$').hasMatch(trimmedValue)) {
      return 'Title cannot contain only numbers';
    }
    final specialCharError = _validateSpecialCharacters(value, 'Title');
    if (specialCharError != null) return specialCharError;
    return null;
  }

  String? _validateOrganization(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmedValue = value.trim();
    if (trimmedValue.length > 40) {
      return 'Organization name must be 40 characters or less';
    }
    if (RegExp(r'^[0-9]+$').hasMatch(trimmedValue)) {
      return 'Organization name cannot contain only numbers';
    }
    final specialCharError = _validateSpecialCharacters(value, 'Organization name');
    if (specialCharError != null) return specialCharError;
    return null;
  }

  String? _validateHours(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter hours';
    }
    final trimmedValue = value.trim();
    final hours = int.tryParse(trimmedValue);
    if (hours == null) return 'Please enter a valid number';
    if (hours < 0) return 'Hours cannot be negative';
    if (hours > 500) return 'Hours must be less than 500';
    return null;
  }

  String? _validateDescription(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmedValue = value.trim();
    if (trimmedValue.length > 200) {
      return 'Description must be at most 200 characters';
    }
    if (RegExp(r'^[0-9]+$').hasMatch(trimmedValue)) {
      return 'Description cannot contain only numbers';
    }
    if (!RegExp(r'[a-zA-Z]').hasMatch(trimmedValue)) {
      return 'Description must contain at least one letter';
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
          _certificateError = null;
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
      debugPrint('📤 Starting upload to ImgBB...');
      final bytes = await _certificateFile!.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final response = await http.post(
        Uri.parse('https://api.imgbb.com/1/upload'),
        body: {
          'key': '0b411c63631d14df85c76a6cdbcf1667',
          'image': base64Image,
          'name': 'volunteering_${userId}_${DateTime.now().millisecondsSinceEpoch}',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final imageUrl = data['data']['url'];
        debugPrint('✅ Upload success: $imageUrl');
        return imageUrl;
      } else {
        debugPrint('❌ Upload failed: ${response.statusCode}');
        throw Exception('Upload failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Upload error: $e');
      _showErrorMessage('Failed to upload certificate. Please check your internet connection.');
      return null;
    }
  }

  Future<void> _saveVolunteering() async {
    if (!_formKey.currentState!.validate()) return;

    if (_certificateFile == null && _existingCertificateUrl == null) {
      setState(() {
        _certificateError = 'Please upload a certificate';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _certificateError = null; // Clear any previous error
    });

    try {
      final docId = await _getUserDocId();
      if (docId == null) {
        _showErrorMessage('Unable to identify user');
        return;
      }

      String? certificateUrl = await _uploadCertificate(docId);
      
      if (certificateUrl == null && _existingCertificateUrl == null) {
        _showErrorMessage('Failed to upload certificate. Please try again.');
        return;
      }

      final volunteeringItem = {
        'title': _titleController.text.trim(),
        'organization': _organizationController.text.trim().isEmpty ? null : _organizationController.text.trim(),
        'hours': int.tryParse(_hoursController.text.trim()),
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'certificateUrl': certificateUrl ?? _existingCertificateUrl,
      };

      final doc = await _firestore.collection('users').doc(docId).get();
      List<dynamic> items = doc.data()?['volunteering'] ?? [];

      if (widget.existingItem != null && widget.itemIndex != null) {
        if (widget.itemIndex! < 0 || widget.itemIndex! >= items.length) {
          _showErrorMessage('Invalid volunteering index');
          return;
        }
        items[widget.itemIndex!] = volunteeringItem;
      } else {
        items.add(volunteeringItem);
      }

      await _firestore.collection('users').doc(docId).update({
        'volunteering': items,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving volunteering: $e');
      if (e is FirebaseException) {
        switch (e.code) {
          case 'permission-denied':
            _showErrorMessage('You do not have permission to save this volunteering');
            break;
          case 'unavailable':
            _showErrorMessage('Network error. Please check your connection');
            break;
          case 'not-found':
            _showErrorMessage('User document not found');
            break;
          default:
            _showErrorMessage('Failed to save volunteering: ${e.message}');
        }
      } else {
        _showErrorMessage('Failed to save volunteering');
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

  void _showCertificateDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxHeight: 400),
                child: _certificateFile != null
                    ? Image.file(_certificateFile!, fit: BoxFit.contain)
                    : _existingCertificateUrl != null
                        ? Image.network(_existingCertificateUrl!, fit: BoxFit.contain)
                        : const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _pickCertificate();
                        },
                        icon: const Icon(Icons.edit, color: Color(0xFF01509B)),
                        label: const Text('Replace', style: TextStyle(color: Color(0xFF01509B))),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF01509B)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _certificateFile = null;
                            _existingCertificateUrl = null;
                          });
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: const Text('Remove', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
@override
Widget build(BuildContext context) {
  const Color kBg = Color(0xFFE6F3FF);
  const Color kTopBar = Color(0xFF0D4F94);

  return Scaffold(
    backgroundColor: kBg,
    body: Column(
      children: [
        // Header section
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: kTopBar,
            borderRadius: const BorderRadius.only(
              bottomRight: Radius.circular(32),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          widget.existingItem != null ? 'Edit Volunteering' : 'Add Volunteering',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTextFieldWithCounter(
                        controller: _titleController,
                        label: 'Title *',
                        hint: 'e.g., Community Cleanup Volunteer',
                        maxLength: 40,
                        validator: _validateTitle,
                      ),
                      const SizedBox(height: 16.0),
                      _buildTextFieldWithCounter(
                        controller: _organizationController,
                        label: 'Organization',
                        hint: 'e.g., Red Crescent Society',
                        maxLength: 40,
                        validator: _validateOrganization,
                      ),
                      const SizedBox(height: 16.0),
                      _buildTextField(
                        controller: _hoursController,
                        label: 'Hours *',
                        hint: 'e.g., 25',
                        keyboardType: TextInputType.number,
                        validator: _validateHours,
                      ),
                      const SizedBox(height: 16.0),
                      _buildCertificatePicker(),
                      const SizedBox(height: 16.0),
                      _buildTextFieldWithCharCounter(
                        controller: _descriptionController,
                        label: 'Description',
                        hint: 'Describe your volunteering activities...',
                        maxLines: 5,
                        minChars: 200,
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
  );
}
  Widget _buildCertificatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Certificate *',
          style: TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF01509B),
          ),
        ),
        const SizedBox(height: 8.0),
        InkWell(
          onTap: () {
            if (_certificateFile != null || _existingCertificateUrl != null) {
              _showCertificatePreview();
            } else {
              _pickCertificate();
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _certificateError != null 
                    ? Colors.red 
                    : const Color(0xFF01509B).withOpacity(0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF01509B).withOpacity(0.05),
                  spreadRadius: 0,
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.upload_file, color: const Color(0xFF01509B)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _certificateFile != null
                        ? 'Certificate selected (tap to view)'
                        : _existingCertificateUrl != null
                            ? 'Certificate uploaded (tap to view)'
                            : 'Tap to upload certificate',
                    style: TextStyle(
                      color: _certificateFile != null || _existingCertificateUrl != null
                          ? const Color(0xFF01509B)
                          : Colors.grey[600],
                    ),
                  ),
                ),
                if (_certificateFile != null || _existingCertificateUrl != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _certificateFile = null;
                        _existingCertificateUrl = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_certificateError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0, left: 12.0),
            child: Text(
              _certificateError!,
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 12.0,
              ),
            ),
          ),
      ],
    );
  }

  void _showCertificatePreview() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _certificateFile != null
                          ? Image.file(_certificateFile!, fit: BoxFit.contain)
                          : _existingCertificateUrl != null
                              ? Image.network(_existingCertificateUrl!, fit: BoxFit.contain)
                              : const SizedBox.shrink(),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
        Text(
          label,
          style: const TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF01509B),
          ),
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          keyboardType: keyboardType,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          inputFormatters: [
            LengthLimitingTextInputFormatter(maxLength),
            NoEmojiInputFormatter(),
          ],
          decoration: _inputDecoration(hint),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4.0, right: 4.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$currentLength/$maxLength',
              style: TextStyle(
                fontSize: 12.0,
                color: currentLength > maxLength ? Colors.red : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextFieldWithCharCounter({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    required int minChars,
    String? Function(String?)? validator,
  }) {
    final currentLength = controller.text.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.w600,
            color: Color(0xFF01509B),
          ),
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          inputFormatters: [
            LengthLimitingTextInputFormatter(minChars),
            NoEmojiInputFormatter(),
          ],
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: _inputDecoration(hint),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4.0, right: 4.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$currentLength/$minChars characters',
              style: TextStyle(
                fontSize: 12.0,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
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
            color: Color(0xFF01509B),
          ),
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          inputFormatters: [
            NoEmojiInputFormatter(),
          ],
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          keyboardType: keyboardType,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[500]),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: const Color(0xFF01509B).withOpacity(0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: const Color(0xFF01509B).withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF01509B), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF01509B), Color(0xFF83C8EF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF01509B).withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveVolunteering,
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