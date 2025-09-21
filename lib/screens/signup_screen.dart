import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'signin_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  // Form Controllers
  final _controllers = _FormControllers();

  // Form State
  final _formState = _FormState();

  bool _isLoading = false;

  @override
  void dispose() {
    _controllers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _AppTheme.gradientBackground,
        child: SafeArea(
          child: Column(
            children: [
              const _AppBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: _SignUpCard(
                    formKey: _formKey,
                    controllers: _controllers,
                    formState: _formState,
                    isLoading: _isLoading,
                    onSignUp: _handleSignUp,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) {
      print("Form validation failed");
      return;
    }

    // Check if all required fields are selected
    if (_formState.selectedMajor == null ||
        _formState.selectedLevel == null ||
        _formState.selectedGender == null) {
      _showErrorMessage('Please fill all required fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      print("Creating user with email: ${_controllers.email.text.trim()}");

      // Create user account
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: _controllers.email.text.trim(),
        password: _controllers.password.text.trim(),
      );

      print("User created successfully: ${userCredential.user?.uid}");

      // Save user data to Firestore
      await _saveUserData(userCredential.user!.uid);

      print("User data saved to Firestore");

      // Send verification email
      await userCredential.user!.sendEmailVerification();
      
      if (mounted) {
        _showSuccessMessage();
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      print("FirebaseAuthException: ${e.code} - ${e.message}");
      if (mounted) _showErrorMessage(_getAuthErrorMessage(e.code));
    } catch (e) {
      print("General error during signup: $e");
      // Even if Firestore fails, the user account was created
      if (mounted) {
        _showSuccessMessage();
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveUserData(String uid) async {
    try {
      print("Saving user data for UID: $uid");

      // Get values safely
      final firstName = _controllers.firstName.text.trim();
      final lastName = _controllers.lastName.text.trim();
      final email = _controllers.email.text.trim();
      final major = _formState.selectedMajor ?? '';
      final level = _getLevelNumber(_formState.selectedLevel ?? '');
      final gender = _formState.selectedGender ?? '';
      
      // Parse GPA safely
      double gpaValue = 0.0;
      final gpaText = _controllers.gpa.text.trim();
      if (gpaText.isNotEmpty) {
        try {
          gpaValue = double.parse(gpaText);
        } catch (e) {
          print("GPA parsing error: $e");
        }
      }

      print("Data to save - Name: $firstName $lastName, Email: $email, Major: $major, Level: $level, Gender: $gender, GPA: $gpaValue");

      // Use the collection reference directly
      final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
      
      await userDoc.set({
        'FName': firstName,
        'LName': lastName,
        'email': email,
        'major': major,
        'level': level,
        'gender': gender,
        'GPA': gpaValue,
        'createdAt': FieldValue.serverTimestamp(),
        'emailVerified': false,
      });
      
      print("User data saved successfully to Firestore");

    } catch (e) {
      print("Firestore save error: $e");
      // Don't rethrow - let the signup complete even if Firestore fails
      // The user account is already created in Firebase Auth
    }
  }

  // Add this helper method to convert level string to number
  int _getLevelNumber(String level) {
    switch (level) {
      case 'Level 3': return 3;
      case 'Level 4': return 4;
      case 'Level 5': return 5;
      case 'Level 6': return 6;
      case 'Level 7': return 7;
      case 'Level 8': return 8;
      default: return 0;
    }
  }

  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'Registration failed: $code. Please try again.';
    }
  }

  void _showSuccessMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Account created successfully! Please check your email to verify your account.'),
        backgroundColor: Color(0xFF4ECDC4),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[400],
      ),
    );
  }
}

/// Custom App Bar with Deep Sea theme
class _AppBar extends StatelessWidget {
  const _AppBar();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
            ),
          ),
          const Expanded(
            child: Text(
              'Create Account',
              style: TextStyle(
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
    );
  }
}

/// Main signup card with glassmorphism effect
class _SignUpCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final _FormControllers controllers;
  final _FormState formState;
  final bool isLoading;
  final VoidCallback onSignUp;

  const _SignUpCard({
    required this.formKey,
    required this.controllers,
    required this.formState,
    required this.isLoading,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0e0259).withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Header(),
              const SizedBox(height: 24),
              _PersonalInfoSection(controllers: controllers),
              const SizedBox(height: 20),
              _AccountInfoSection(controllers: controllers),
              const SizedBox(height: 20),
              _AcademicInfoSection(
                controllers: controllers,
                formState: formState,
              ),
              const SizedBox(height: 28),
              _SignUpButton(isLoading: isLoading, onPressed: onSignUp),
              const SizedBox(height: 16),
              const _SignInPrompt(),
            ],
          ),
        ),
      ),
    );
  }
}
class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0097b2), Color(0xFF006B7A), Color(0xFF0e0259)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0097b2).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/images/logo.png',
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Join ABSHERK',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0e0259),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Create your academic companion account',
          style: TextStyle(
            fontSize: 14,
            color: const Color(0xFF0e0259).withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
/// Personal information input section
class _PersonalInfoSection extends StatelessWidget {
  final _FormControllers controllers;

  const _PersonalInfoSection({required this.controllers});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Personal Information', icon: Icons.person_outline_rounded),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CustomTextField(
                controller: controllers.firstName,
                label: 'First Name',
                icon: Icons.badge_outlined,
                validator: _Validators.required('first name'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CustomTextField(
                controller: controllers.lastName,
                label: 'Last Name',
                icon: Icons.badge_outlined,
                validator: _Validators.required('last name'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Account credentials section
class _AccountInfoSection extends StatelessWidget {
  final _FormControllers controllers;

  const _AccountInfoSection({required this.controllers});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Account Information', icon: Icons.security_rounded),
        const SizedBox(height: 12),
        _CustomTextField(
          controller: controllers.email,
          label: 'University Email',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
          hint: 'student@student.ksu.edu.sa',
          validator: _Validators.email,
        ),
        const SizedBox(height: 12),
        _PasswordFieldWithRequirements(
          controller: controllers.password,
          label: 'Password',
        ),
        const SizedBox(height: 12),
        _PasswordField(
          controller: controllers.confirmPassword,
          label: 'Confirm Password',
          validator: (value) => _Validators.confirmPassword(value, controllers.password.text),
        ),
      ],
    );
  }
}

/// Academic information section
class _AcademicInfoSection extends StatelessWidget {
  final _FormControllers controllers;
  final _FormState formState;

  const _AcademicInfoSection({
    required this.controllers,
    required this.formState,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Academic Information', icon: Icons.school_rounded),
        const SizedBox(height: 12),
        _CustomDropdown<String>(
          value: formState.selectedMajor,
          label: 'Major',
          icon: Icons.science_outlined,
          items: _Constants.majors,
          onChanged: (value) => formState.selectedMajor = value,
          validator: _Validators.required('major'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _CustomDropdown<String>(
                value: formState.selectedLevel,
                label: 'Level',
                icon: Icons.trending_up_rounded,
                items: _Constants.levels,
                onChanged: (value) => formState.selectedLevel = value,
                validator: _Validators.required('level'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CustomDropdown<String>(
                value: formState.selectedGender,
                label: 'Gender',
                icon: Icons.person_pin_rounded,
                items: _Constants.genders,
                onChanged: (value) => formState.selectedGender = value,
                validator: _Validators.required('gender'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _CustomTextField(
          controller: controllers.gpa,
          label: 'Current GPA',
          icon: Icons.grade_rounded,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          hint: 'e.g., 3.75',
          validator: _Validators.gpa,
        ),
      ],
    );
  }
}

/// Password field with detailed requirements feedback
class _PasswordFieldWithRequirements extends StatefulWidget {
  final TextEditingController controller;
  final String label;

  const _PasswordFieldWithRequirements({
    required this.controller,
    required this.label,
  });

  @override
  State<_PasswordFieldWithRequirements> createState() => _PasswordFieldWithRequirementsState();
}

class _PasswordFieldWithRequirementsState extends State<_PasswordFieldWithRequirements> {
  bool _obscureText = true;
  String _currentPassword = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      setState(() {
        _currentPassword = widget.controller.text;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final requirements = _getPasswordRequirements(_currentPassword);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          obscureText: _obscureText,
          validator: _Validators.password,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF006B7A), size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: const Color(0xFF006B7A),
                size: 20,
              ),
              onPressed: () => setState(() => _obscureText = !_obscureText),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: const Color(0xFF4ECDC4).withOpacity(0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
            ),
            filled: true,
            fillColor: const Color(0xFF95E1D3).withOpacity(0.1),
            labelStyle: TextStyle(color: const Color(0xFF006B7A).withOpacity(0.8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        if (_currentPassword.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...requirements.map((req) => _PasswordRequirement(
            text: req.text,
            isValid: req.isValid,
          )),
        ],
      ],
    );
  }

  List<PasswordRequirement> _getPasswordRequirements(String password) {
    return [
      PasswordRequirement(
        text: 'At least 8 characters',
        isValid: password.length >= 8,
      ),
      PasswordRequirement(
        text: 'One uppercase letter',
        isValid: password.contains(RegExp(r'[A-Z]')),
      ),
      PasswordRequirement(
        text: 'One lowercase letter',
        isValid: password.contains(RegExp(r'[a-z]')),
      ),
      PasswordRequirement(
        text: 'One number',
        isValid: password.contains(RegExp(r'[0-9]')),
      ),
      PasswordRequirement(
        text: 'One special character (@\$!%*?&)',
        isValid: password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]')),
      ),
    ];
  }
}

/// Password requirement indicator
class _PasswordRequirement extends StatelessWidget {
  final String text;
  final bool isValid;

  const _PasswordRequirement({
    required this.text,
    required this.isValid,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            isValid ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: isValid ? const Color(0xFF4ECDC4) : Colors.grey[400],
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isValid ? const Color(0xFF006B7A) : Colors.grey[600],
                fontWeight: isValid ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PasswordRequirement {
  final String text;
  final bool isValid;

  PasswordRequirement({required this.text, required this.isValid});
}

/// Custom text field with consistent styling
class _CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final TextInputType? keyboardType;
  final String? Function(String?) validator;

  const _CustomTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.keyboardType,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF006B7A), size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF4ECDC4).withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFF95E1D3).withOpacity(0.1),
        labelStyle: TextStyle(color: const Color(0xFF006B7A).withOpacity(0.8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

/// Password field with visibility toggle
class _PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;

  const _PasswordField({
    required this.controller,
    required this.label,
    required this.validator,
  });

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscureText,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF006B7A), size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: const Color(0xFF006B7A),
            size: 20,
          ),
          onPressed: () => setState(() => _obscureText = !_obscureText),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF4ECDC4).withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFF95E1D3).withOpacity(0.1),
        labelStyle: TextStyle(color: const Color(0xFF006B7A).withOpacity(0.8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

/// Custom dropdown with consistent styling
class _CustomDropdown<T> extends StatefulWidget {
  final T? value;
  final String label;
  final IconData icon;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String? Function(T?) validator;

  const _CustomDropdown({
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.onChanged,
    required this.validator,
  });

  @override
  State<_CustomDropdown<T>> createState() => _CustomDropdownState<T>();
}

class _CustomDropdownState<T> extends State<_CustomDropdown<T>> {
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: widget.value,
      validator: widget.validator,
      onChanged: (value) {
        setState(() {
          widget.onChanged(value);
        });
      },
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.icon, color: const Color(0xFF006B7A), size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: const Color(0xFF4ECDC4).withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFF95E1D3).withOpacity(0.1),
        labelStyle: TextStyle(color: const Color(0xFF006B7A).withOpacity(0.8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: widget.items.map((T item) {
        return DropdownMenuItem<T>(
          value: item,
          child: Text(
            item.toString(),
            style: const TextStyle(fontSize: 14),
          ),
        );
      }).toList(),
    );
  }
}

/// Section title with icon
class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF0097b2), size: 18),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0e0259),
          ),
        ),
      ],
    );
  }
}

/// Sign up button
class _SignUpButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const _SignUpButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_add_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account? ',
          style: TextStyle(
            color: const Color(0xFF0e0259).withOpacity(0.7),
            fontSize: 14,
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, _) => const SignInScreen(),
                transitionsBuilder: (context, animation, _, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    )),
                    child: child,
                  );
                },
                transitionDuration: const Duration(milliseconds: 400),
              ),
            );
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
          ),
          child: const Text(
            'Sign In',
            style: TextStyle(
              color: Color(0xFF0097b2),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
/// Form controllers manager
class _FormControllers {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final gpa = TextEditingController();

  void dispose() {
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    gpa.dispose();
  }
}

/// Form state manager
class _FormState {
  String? selectedMajor;
  String? selectedLevel;
  String? selectedGender;
}

/// Input validators
class _Validators {
  static String? Function(String?) required(String fieldName) {
    return (value) {
      if (value == null || value.trim().isEmpty) {
        return 'Please enter your $fieldName';
      }
      return null;
    };
  }
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your university email';
    }
    // Match exactly 8 digits before @student.ksu.edu.sa
    final emailPattern = RegExp(r'^\d{8}@student\.ksu\.edu\.sa$');
    if (!emailPattern.hasMatch(value.trim())) {
      return 'Email must be 8 digits followed by @student.ksu.edu.sa';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters long';
    }
    if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*(),.?":{}|<>])[A-Za-z\d!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Password must meet all requirements above';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != password) {
      return 'Passwords do not match';
    }
    return null;
  }

  static String? gpa(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your current GPA';
    }
    final gpaValue = double.tryParse(value.trim());
    if (gpaValue == null) {
      return 'Please enter a valid GPA';
    }
    if (gpaValue < 0 || gpaValue > 5) {
      return 'GPA must be between 0.00 and 5.00';
    }
    return null;
  }
}
/// App constants
class _Constants {
  static const List<String> majors = [
    'Computer Science',
    'Software Engineering',
    'Information Technology',
    'Information Systems',
  ];

  static const List<String> levels = [
    'Level 3',
    'Level 4',
    'Level 5',
    'Level 6',
    'Level 7',
    'Level 8'
  ];

  static const List<String> genders = ['Male', 'Female'];
}
/// App theme constants
class _AppTheme {
  static const gradientBackground = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF006B7A), // Deep ocean teal
        Color(0xFF0097b2), // Bright teal
        Color(0xFF0e0259), // Deep navy depths
      ],
      stops: [0.0, 0.6, 1.0],
    ),
  );
}