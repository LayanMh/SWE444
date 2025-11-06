import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class ProjectFormPage extends StatefulWidget {
  final Map<String, dynamic>? existingItem;
  final int? itemIndex;

  const ProjectFormPage({super.key, this.existingItem, this.itemIndex});

  @override
  State<ProjectFormPage> createState() => _ProjectFormPageState();
}

class _ProjectFormPageState extends State<ProjectFormPage> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  late TextEditingController _titleController;
  late TextEditingController _organizationController;
  late TextEditingController _linkController;
  late TextEditingController _descriptionController;
  
  String? _startMonth;
  int? _startYear;
  String? _endMonth;
  int? _endYear;
  bool _isCurrentlyActive = false;
  bool _isSaving = false;
  
  String? _dateError;

  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.existingItem?['title'] ?? '');
    _organizationController = TextEditingController(text: widget.existingItem?['organization'] ?? '');
    _linkController = TextEditingController(text: widget.existingItem?['link'] ?? '');
    _descriptionController = TextEditingController(text: widget.existingItem?['description'] ?? '');
    _isCurrentlyActive = widget.existingItem?['isCurrentlyActive'] ?? false;
    
    // Add listeners to trigger rebuild for character counter
    _titleController.addListener(() => setState(() {}));
    _organizationController.addListener(() => setState(() {}));
    _descriptionController.addListener(() => setState(() {}));
    
    if (widget.existingItem?['startDate'] != null) {
      final parts = widget.existingItem!['startDate'].split(' ');
      if (parts.length == 2) {
        _startMonth = parts[0];
        _startYear = int.tryParse(parts[1]);
      }
    }
    
    if (widget.existingItem?['endDate'] != null && widget.existingItem!['endDate'] != 'Present') {
      final parts = widget.existingItem!['endDate'].split(' ');
      if (parts.length == 2) {
        _endMonth = parts[0];
        _endYear = int.tryParse(parts[1]);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _organizationController.dispose();
    _linkController.dispose();
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
      return 'Please enter a project title';
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
    
    if (trimmedValue.length > 30) {
      return 'Organization name must be 30 characters or less';
    }
    
    if (RegExp(r'^[0-9]+$').hasMatch(trimmedValue)) {
      return 'Organization name cannot contain only numbers';
    }
    
    return null;
  }

  // Validation: Link/URL
  String? _validateLink(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    
   final trimmedValue = value.trim().toLowerCase();
    
    if (!trimmedValue.startsWith('http://github.com/') &&
        !trimmedValue.startsWith('https://github.com/')) {
      return 'Link must be a GitHub URL https://github.com/';
    }
    
    if (trimmedValue.length > 500) {
      return 'URL must be 500 characters or less';
    }
    
    return null;
  }

  // Validation: Description
 String? _validateDescription(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null; 
  }
  
  final trimmedValue = value.trim();

  if (trimmedValue.length > 200) {
    return 'Description must be at most 200 characters';
  }
  
  if (RegExp(r'^[0-9]+$').hasMatch(trimmedValue)) {
    return 'Description cannot contain only numbers';
  }
  
  return null;
}
  // Validation: Date Range
  String? _validateDateRange() {
    if (_startMonth == null || _startYear == null || _isCurrentlyActive) {
      return null;
    }
    
    if (_endMonth == null || _endYear == null) {
      return null;
    }
    
    final startMonthIndex = _months.indexOf(_startMonth!);
    final endMonthIndex = _months.indexOf(_endMonth!);
    
    if (_endYear! < _startYear!) {
      return 'End date must be after start date';
    }
    
    if (_endYear == _startYear && endMonthIndex < startMonthIndex) {
      return 'End date must be after start date';
    }
    
    return null;
  }

  // Validation: Future Date
  String? _validateFutureDate() {
    final now = DateTime.now();
    final currentYear = now.year;
    final currentMonthIndex = now.month - 1;
    
    if (_startMonth != null && _startYear != null) {
      final startMonthIndex = _months.indexOf(_startMonth!);
      
      if (_startYear! > currentYear) {
        return 'Start date cannot be in the future';
      }
      
      if (_startYear == currentYear && startMonthIndex > currentMonthIndex) {
        return 'Start date cannot be in the future';
      }
    }
    
    if (!_isCurrentlyActive && _endMonth != null && _endYear != null) {
      final endMonthIndex = _months.indexOf(_endMonth!);
      
      if (_endYear! > currentYear) {
        return 'End date cannot be in the future';
      }
      
      if (_endYear == currentYear && endMonthIndex > currentMonthIndex) {
        return 'End date cannot be in the future';
      }
    }
    
    return null;
  }

  void _validateDates() {
    setState(() {
      final dateRangeError = _validateDateRange();
      final futureDateError = _validateFutureDate();
      _dateError = dateRangeError ?? futureDateError;
    });
  }

  Future<void> _saveProject() async {
    if (!_formKey.currentState!.validate()) return;

    _validateDates();
    if (_dateError != null) return;

    setState(() => _isSaving = true);

    try {
      final docId = await _getUserDocId();
      if (docId == null) {
        _showErrorMessage('Unable to identify user');
        return;
      }

      final projectItem = {
        'title': _titleController.text.trim(),
        'organization': _organizationController.text.trim(),
        'link': _linkController.text.trim(),
        'startDate': _startMonth != null && _startYear != null ? '$_startMonth $_startYear' : null,
        'endDate': _isCurrentlyActive ? 'Present' : (_endMonth != null && _endYear != null ? '$_endMonth $_endYear' : null),
        'description': _descriptionController.text.trim(),
        'isCurrentlyActive': _isCurrentlyActive,
      };

      final doc = await _firestore.collection('users').doc(docId).get();
      List<dynamic> items = doc.data()?['projects'] ?? [];

      if (widget.existingItem != null && widget.itemIndex != null) {
        if (widget.itemIndex! < 0 || widget.itemIndex! >= items.length) {
          _showErrorMessage('Invalid project index');
          return;
        }
        items[widget.itemIndex!] = projectItem;
      } else {
        items.add(projectItem);
      }

      await _firestore.collection('users').doc(docId).update({
        'projects': items,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving project: $e');
      
      if (e is FirebaseException) {
        switch (e.code) {
          case 'permission-denied':
            _showErrorMessage('You do not have permission to save this project');
            break;
          case 'unavailable':
            _showErrorMessage('Network error. Please check your connection');
            break;
          case 'not-found':
            _showErrorMessage('User document not found');
            break;
          default:
            _showErrorMessage('Failed to save project: ${e.message}');
        }
      } else {
        _showErrorMessage('Failed to save project');
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
        backgroundColor: Colors.red[400],
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
                        widget.existingItem != null ? 'Edit Project' : 'Add Project',
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
                              label: 'Project Title *',
                              hint: 'e.g., AI Research Project',
                              maxLength: 30,
                              validator: _validateTitle,
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextFieldWithCounter(
                              controller: _organizationController,
                              label: 'Organization',
                              hint: 'e.g., Google Developer Student Club',
                              maxLength: 30,
                              validator: _validateOrganization,
                            ),
                            const SizedBox(height: 16.0),
                            _buildTextField(
                              controller: _linkController,
                              label: 'Link/Attachment',
                              hint: 'e.g., https://github.com/yourproject',
                              validator: _validateLink,
                            ),
                            const SizedBox(height: 16.0),
                            _buildDatePicker(
                              label: 'Start Date',
                              selectedMonth: _startMonth,
                              selectedYear: _startYear,
                              onMonthChanged: (month) {
                                setState(() => _startMonth = month);
                                _validateDates();
                              },
                              onYearChanged: (year) {
                                setState(() => _startYear = year);
                                _validateDates();
                              },
                            ),
                            const SizedBox(height: 16.0),
                            CheckboxListTile(
                              title: const Text('Currently working on this'),
                              value: _isCurrentlyActive,
                              onChanged: (value) {
                                setState(() {
                                  _isCurrentlyActive = value ?? false;
                                  if (_isCurrentlyActive) {
                                    _endMonth = null;
                                    _endYear = null;
                                  }
                                });
                                _validateDates();
                              },
                              activeColor: const Color(0xFF0097b2),
                              contentPadding: EdgeInsets.zero,
                            ),
                            if (!_isCurrentlyActive) ...[
                              _buildDatePicker(
                                label: 'End Date',
                                selectedMonth: _endMonth,
                                selectedYear: _endYear,
                                onMonthChanged: (month) {
                                  setState(() => _endMonth = month);
                                  _validateDates();
                                },
                                onYearChanged: (year) {
                                  setState(() => _endYear = year);
                                  _validateDates();
                                },
                              ),
                            ],
                            if (_dateError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  _dateError!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16.0),
                          _buildTextFieldWithWordCounter(
  controller: _descriptionController,
  label: 'Description',  // ← Removed asterisk
  hint: 'Describe your project...',
  maxLines: 5,
  minWords: 200,
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

  Widget _buildDatePicker({
    required String label,
    required String? selectedMonth,
    required int? selectedYear,
    required Function(String?) onMonthChanged,
    required Function(int?) onYearChanged,
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
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: selectedMonth,
                decoration: _inputDecoration('Month'),
                items: _months.map((month) {
                  return DropdownMenuItem(value: month, child: Text(month));
                }).toList(),
                onChanged: onMonthChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: selectedYear,
                decoration: _inputDecoration('Year'),
                items: List.generate(26, (index) => 2025 - index).map((year) {
                  return DropdownMenuItem(value: year, child: Text('$year'));
                }).toList(),
                onChanged: onYearChanged,
              ),
            ),
          ],
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
            color: Color(0xFF0e0259),
          ),
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          inputFormatters: [
            LengthLimitingTextInputFormatter(maxLength),
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

  Widget _buildTextFieldWithWordCounter({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    required int minWords,
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
            color: Color(0xFF0e0259),
          ),
        ),
        const SizedBox(height: 8.0),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          autovalidateMode: AutovalidateMode.disabled,
          decoration: _inputDecoration(hint),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4.0, right: 4.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$currentLength/$minWords characters',
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
          autovalidateMode: AutovalidateMode.onUserInteraction,
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
        onPressed: _isSaving ? null : _saveProject,
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