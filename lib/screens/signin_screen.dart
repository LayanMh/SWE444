import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'signup_screen.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter/services.dart';
import 'reset_password.dart';
import 'welcome_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  // Microsoft OAuth2 constants
  final String _msClientId = 'adba7fb2-f6d3-4fef-950d-e0743a720212';
  final String _msTenantId = '19df06c3-3fcd-4947-809f-064684abf608';
  final String _msRedirectUri = 'msauth://com.example.absherk/redirect';
  final FlutterAppAuth _appAuth = FlutterAppAuth();

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  // Load saved credentials when the screen initializes
  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    final savedPassword = prefs.getString('saved_password');
    final rememberMe = prefs.getBool('remember_me') ?? false;

    if (rememberMe && savedEmail != null && savedPassword != null) {
      setState(() {
        _emailController.text = savedEmail;
        _passwordController.text = savedPassword;
        _rememberMe = true;
      });
    }
  }

  // Save credentials when remember me is checked
  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (_rememberMe) {
      await prefs.setString('saved_email', _emailController.text.trim());
      await prefs.setString('saved_password', _passwordController.text.trim());
      await prefs.setBool('remember_me', true);
    } else {
      // Clear saved credentials if remember me is unchecked
      await prefs.remove('saved_email');
      await prefs.remove('saved_password');
      await prefs.setBool('remember_me', false);
    }
  }
Future<void> _handleMicrosoftSignIn() async {
  setState(() => _isLoading = true);

  try {
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        _msClientId,
        _msRedirectUri,
        serviceConfiguration: AuthorizationServiceConfiguration(
          authorizationEndpoint:
              'https://login.microsoftonline.com/$_msTenantId/oauth2/v2.0/authorize',
          tokenEndpoint:
              'https://login.microsoftonline.com/$_msTenantId/oauth2/v2.0/token',
        ),
        scopes: ['openid', 'profile', 'email', 'User.Read'],
        // Always force login - ignore remember me for Microsoft
        promptValues: ['login'],
        additionalParameters: {
          'domain_hint': 'student.ksu.edu.sa',
        },
      ),
    );

    if (result != null) {
      // Microsoft sign-in successful - save preference if remember me is checked
      if (_rememberMe) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('microsoft_remember_me', true);
        await prefs.setString('microsoft_last_email', '');
      }

      // Get user info from Microsoft Graph API
      final userInfo = await _getUserInfoFromMicrosoft(result.accessToken!);
      userInfo['accessToken'] = result.accessToken!;
      
      // Check if this is a first-time Microsoft user
      final isFirstTime = await _checkIfFirstTimeUser(userInfo['email']);
      
      if (isFirstTime) {
        // First time Microsoft user - redirect to profile completion
        if (mounted) {
          _showSuccessMessage('Welcome! Please complete your profile to continue.');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => MicrosoftUserProfileForm(
                microsoftUserInfo: userInfo,
                accessToken: result.accessToken!,
              ),
            ),
          );
        }
      } else {
        // Existing user - proceed to home directly
        _showSuccessMessage('Signed in with Microsoft successfully!');
        _goToHome();
      }
    }
  } on PlatformException catch (e) {
    if (e.code == 'access_denied' ||
        e.code == 'authorize_and_exchange_code_cancelled') {
      return;
    }
    debugPrint('Microsoft Sign-In Platform Exception: ${e.code} - ${e.message}');
    _showErrorMessage('Microsoft Sign-In was cancelled or denied.');
  } catch (e, stackTrace) {
    debugPrint('Microsoft Sign-In failed: $e');
    debugPrintStack(stackTrace: stackTrace);
    _showErrorMessage('Microsoft Sign-In failed. Please try again.');
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}
  Future<Map<String, dynamic>> _getUserInfoFromMicrosoft(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('https://graph.microsoft.com/v1.0/me'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        return {
          'email': userData['mail'] ?? userData['userPrincipalName'] ?? 'unknown@student.ksu.edu.sa',
          'firstName': userData['givenName'] ?? '',
          'lastName': userData['surname'] ?? '',
          'microsoftId': userData['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'displayName': userData['displayName'] ?? 'Unknown User',
        };
      } else {
        debugPrint('Microsoft Graph API error: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to fetch user info from Microsoft: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching Microsoft user info: $e');
      // Return default values if API call fails
      return {
        'email': 'unknown@student.ksu.edu.sa',
        'firstName': 'Unknown',
        'lastName': 'User',
        'microsoftId': DateTime.now().millisecondsSinceEpoch.toString(),
        'displayName': 'Unknown User',
      };
    }
  }

  Future<void> _signInExistingMicrosoftUser(Map<String, dynamic> userInfo) async {
    try {
      // Create a custom token or use Anonymous auth, then link the Microsoft account
      final UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
      
      // Update the user's display name
      await userCredential.user?.updateDisplayName(userInfo['displayName']);
      
      debugPrint('Existing Microsoft user signed in successfully');
    } catch (e) {
      debugPrint('Error signing in existing Microsoft user: $e');
      throw e;
    }
  }

  Future<bool> _checkIfFirstTimeUser(String email) async {
    try {
      // Check by email first (simpler approach)
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      
      return userDoc.docs.isEmpty; // True if no user found (first time)
    } catch (e) {
      debugPrint('Error checking user existence: $e');
      return true; // Assume first time if error occurs
    }
  }

  // Add method to check for auto-login on app startup
  Future<bool> checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_me') ?? false;
    final microsoftRememberMe = prefs.getBool('microsoft_remember_me') ?? false;
    
    if (rememberMe) {
      final savedEmail = prefs.getString('saved_email');
      final savedPassword = prefs.getString('saved_password');
      
      if (savedEmail != null && savedPassword != null) {
        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: savedEmail,
            password: savedPassword,
          );
          return true; // Auto-login successful
        } catch (e) {
          // Clear invalid saved credentials
          await prefs.remove('saved_email');
          await prefs.remove('saved_password');
          await prefs.setBool('remember_me', false);
          return false;
        }
      }
    }
    
    return false; // No auto-login
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: _SignInCard(
                    formKey: _formKey,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    obscurePassword: _obscurePassword,
                    rememberMe: _rememberMe,
                    isLoading: _isLoading,
                    onTogglePassword: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    onRememberMeChanged: (value) =>
                        setState(() => _rememberMe = value ?? false),
                    onSignIn: _handleSignIn,
                    onForgotPassword: _handleForgotPassword,
                    onMicrosoftSignIn: _handleMicrosoftSignIn,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Save credentials if remember me is checked
      await _saveCredentials();

      if (mounted) {
        _showSuccessMessage('Welcome back to ABSHERK!');
        _goToHome();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        _showErrorMessage(_getErrorMessage(e.code));
      }
    } catch (e, stackTrace) {
      debugPrint('Sign in error: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _showErrorMessage('An unexpected error occurred. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToHome() {
    if (!mounted) {
      return;
    }
    Navigator.pushReplacementNamed(context, '/home');
  }

  void _handleForgotPassword() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, _) => const ResetPasswordScreen(),
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
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'Sign in failed. Please try again.';
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF4ECDC4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[400],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// Microsoft User Profile Completion Form
class MicrosoftUserProfileForm extends StatefulWidget {
  final Map<String, dynamic> microsoftUserInfo;
  final String accessToken;

  const MicrosoftUserProfileForm({
    super.key,
    required this.microsoftUserInfo,
    required this.accessToken,
  });

  @override
  State<MicrosoftUserProfileForm> createState() => _MicrosoftUserProfileFormState();
}

class _MicrosoftUserProfileFormState extends State<MicrosoftUserProfileForm> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _gpaController = TextEditingController();
  
  String? _selectedMajor;
  int? _selectedLevel;
  String? _selectedGender;
  bool _isLoading = false;

  // Fetch arrays from Firebase like in signup screen
  Future<List<String>> getArrayFromFirebase(String fieldName) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc("1AceMLnpzHNptVsj5gakR4qcYX12").get();
      if (doc.exists && doc.data()?[fieldName] != null) {
        return List<String>.from(doc.data()![fieldName]);
      }
    } catch (e) {
      debugPrint('Error fetching $fieldName: $e');
    }
    return []; // fallback empty list
  }

  Future<List<int>> getArrayFromFirebaseInt(String fieldName) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc("1AceMLnpzHNptVsj5gakR4qcYX12")
          .get();
      if (doc.exists && doc.data()?[fieldName] != null) {
        // Convert dynamic list to int list
        return List<int>.from(doc.data()![fieldName]);
      }
    } catch (e) {
      debugPrint('Error fetching $fieldName: $e');
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    // Pre-populate name fields if available from Microsoft
    _firstNameController.text = widget.microsoftUserInfo['firstName'] ?? '';
    _lastNameController.text = widget.microsoftUserInfo['lastName'] ?? '';
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _gpaController.dispose();
    super.dispose();
  }

  Future<void> _saveUserProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedMajor == null || _selectedLevel == null || _selectedGender == null) {
      _showErrorMessage('Please fill all required fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Parse GPA safely
      double gpaValue = 0.0;
      final gpaText = _gpaController.text.trim();
      if (gpaText.isNotEmpty) {
        gpaValue = double.parse(gpaText);
      }

      // Generate a unique document ID using Microsoft ID
      final docId = 'ms_${widget.microsoftUserInfo['microsoftId']}';

      // Save user data directly to Firestore without Firebase Auth
      await FirebaseFirestore.instance
          .collection('users')
          .doc(docId)
          .set({
        'FName': _firstNameController.text.trim(),
        'LName': _lastNameController.text.trim(),
        'email': widget.microsoftUserInfo['email'],
        'major': _selectedMajor,
        'level': _selectedLevel,
        'gender': _selectedGender,
        'GPA': gpaValue,
        'microsoftId': widget.microsoftUserInfo['microsoftId'],
        'authProvider': 'microsoft',
        'createdAt': FieldValue.serverTimestamp(),
        'emailVerified': true,
        'accountStatus': 'active',
        'isProfileComplete': true,
        'accessToken': widget.accessToken,
        'displayName': '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
      });

      if (mounted) {
        _showSuccessMessage('Profile completed successfully!');
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      debugPrint('Error saving profile: $e');
      _showErrorMessage('Failed to save profile. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF4ECDC4),
        duration: const Duration(seconds: 3),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF006B7A),
              Color(0xFF0097b2),
              Color(0xFF0e0259),
            ],
            stops: [0.0, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildProfileForm(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Complete Your Profile',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileForm() {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0e0259).withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildWelcomeText(),
            const SizedBox(height: 24),
            _buildNameFields(),
            const SizedBox(height: 16),
            _buildMajorDropdown(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildLevelDropdown()),
                const SizedBox(width: 12),
                Expanded(child: _buildGenderDropdown()),
              ],
            ),
            const SizedBox(height: 16),
            _buildGPAField(),
            const SizedBox(height: 32),
            _buildCompleteButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
          'Welcome to ABSHERK',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0e0259),
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeText() {
    return Column(
      children: [
        const SizedBox(height: 8),
        Text(
          'Please complete your academic profile to get started.',
          style: TextStyle(
            fontSize: 14,
            color: const Color(0xFF0e0259).withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildNameFields() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _firstNameController,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your first name';
              }
              return null;
            },
            decoration: _inputDecoration('First Name'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: _lastNameController,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your last name';
              }
              return null;
            },
            decoration: _inputDecoration('Last Name'),
          ),
        ),
      ],
    );
  }

  Widget _buildMajorDropdown() {
    return FutureBuilder<List<String>>(
      future: getArrayFromFirebase('major'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        return DropdownButtonFormField<String>(
          value: _selectedMajor,
          validator: (value) => value == null ? 'Please select your major' : null,
          onChanged: (value) => setState(() => _selectedMajor = value),
          decoration: _inputDecoration('Major'),
          items: snapshot.data!.map((major) {
            return DropdownMenuItem<String>(
              value: major,
              child: Text(major, style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildLevelDropdown() {
    return FutureBuilder<List<int>>(
      future: getArrayFromFirebaseInt('level'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        return DropdownButtonFormField<int>(
          value: _selectedLevel,
          validator: (value) => value == null ? 'Please select your level' : null,
          onChanged: (value) => setState(() => _selectedLevel = value),
          decoration: _inputDecoration('Level'),
          items: snapshot.data!.map((level) {
            return DropdownMenuItem<int>(
              value: level,
              child: Text('Level $level', style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildGenderDropdown() {
    return FutureBuilder<List<String>>(
      future: getArrayFromFirebase('gender'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        return DropdownButtonFormField<String>(
          value: _selectedGender,
          validator: (value) => value == null ? 'Please select gender' : null,
          onChanged: (value) => setState(() => _selectedGender = value),
          decoration: _inputDecoration('Gender'),
          items: snapshot.data!.map((gender) {
            return DropdownMenuItem<String>(
              value: gender,
              child: Text(gender, style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildGPAField() {
    return TextFormField(
      controller: _gpaController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter your current GPA';
        }
        final gpa = double.tryParse(value.trim());
        if (gpa == null || gpa < 0 || gpa > 5) {
          return 'GPA must be between 0.00 and 5.00';
        }
        return null;
      },
      decoration: _inputDecoration('Current GPA', hint: 'e.g., 3.75'),
    );
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: const Color(0xFF4ECDC4).withOpacity(0.5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
      ),
      filled: true,
      fillColor: const Color(0xFF95E1D3).withOpacity(0.1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _buildCompleteButton() {
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
        onPressed: _isLoading ? null : _saveUserProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isLoading
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
                  Icon(Icons.check_circle_outline, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Complete Profile',
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

/// Custom App Bar with Deep Sea theme - FIXED VERSION
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
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: IconButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                  (route) => false,
                );
              },
              icon: const Icon(
                Icons.arrow_back_ios_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              'Welcome Back',
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

/// Main sign in card with glassmorphism effect
class _SignInCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool rememberMe;
  final bool isLoading;
  final VoidCallback onTogglePassword;
  final ValueChanged<bool?> onRememberMeChanged;
  final VoidCallback onSignIn;
  final VoidCallback onForgotPassword;
  final VoidCallback onMicrosoftSignIn;

  const _SignInCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.rememberMe,
    required this.isLoading,
    required this.onTogglePassword,
    required this.onRememberMeChanged,
    required this.onSignIn,
    required this.onForgotPassword,
    required this.onMicrosoftSignIn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0e0259).withValues(alpha: 0.1),
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
              const SizedBox(height: 32),
              _buildEmailField(),
              const SizedBox(height: 16),
              _buildPasswordField(),
              const SizedBox(height: 20),
              _buildRememberMeRow(),
              const SizedBox(height: 32),
              _buildSignInButton(),
              const SizedBox(height: 24),
              _buildDivider(),
              const SizedBox(height: 24),
              _buildSocialSignIn(),
              const SizedBox(height: 24),
              const _SignUpPrompt(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(text: 'University Email'),
        const SizedBox(height: 8),
        TextFormField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          validator: _Validators.email,
          decoration: InputDecoration(
            hintText: 'student@student.ksu.edu.sa',
            prefixIcon: const Icon(
              Icons.alternate_email_rounded,
              color: Color(0xFF006B7A),
              size: 20,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: const Color(0xFF4ECDC4).withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
            ),
            filled: true,
            fillColor: const Color(0xFF95E1D3).withValues(alpha: 0.1),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(text: 'Password'),
        const SizedBox(height: 8),
        TextFormField(
          controller: passwordController,
          obscureText: obscurePassword,
          validator: _Validators.password,
          decoration: InputDecoration(
            hintText: '••••••••••',
            prefixIcon: const Icon(
              Icons.lock_outline_rounded,
              color: Color(0xFF006B7A),
              size: 20,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: const Color(0xFF006B7A),
                size: 20,
              ),
              onPressed: onTogglePassword,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: const Color(0xFF4ECDC4).withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0097b2), width: 2),
            ),
            filled: true,
            fillColor: const Color(0xFF95E1D3).withValues(alpha: 0.1),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRememberMeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Transform.scale(
              scale: 0.9,
              child: Checkbox(
                value: rememberMe,
                onChanged: onRememberMeChanged,
                activeColor: const Color(0xFF4ECDC4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const Text(
              'Remember me',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF0e0259),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: onForgotPassword,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
          ),
          child: const Text(
            'Forgot password?',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF0097b2),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignInButton() {
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
            color: const Color(0xFF0097b2).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onSignIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
                  Icon(Icons.login_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Sign In',
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

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey[300])),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or continue with',
            style: TextStyle(
              fontSize: 12,
              color: const Color(0xFF0e0259).withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey[300])),
      ],
    );
  }

  Widget _buildSocialSignIn() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SocialButton(
          imagePath: 'assets/images/Microsoft.png',
          onPressed: onMicrosoftSignIn,
        ),
      ],
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
                color: const Color(0xFF0097b2).withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/images/logo.png',
              width: 32,
              height: 32,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Welcome Back',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0e0259),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sign in to continue your academic journey',
          style: TextStyle(
            fontSize: 14,
            color: const Color(0xFF0e0259).withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0e0259),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String? imagePath;
  final VoidCallback onPressed;

  const _SocialButton({this.imagePath, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF95E1D3).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF4ECDC4).withValues(alpha: 0.3),
        ),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: imagePath != null
            ? Image.asset(imagePath!, width: 24, height: 24)
            : const Icon(
                Icons.handshake_rounded,
                color: Color(0xFF006B7A),
                size: 24,
              ),
      ),
    );
  }
}

class _SignUpPrompt extends StatelessWidget {
  const _SignUpPrompt();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Don't have an account? ",
          style: TextStyle(
            color: const Color(0xFF0e0259).withValues(alpha: 0.7),
            fontSize: 14,
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, _) => const SignUpScreen(),
                transitionsBuilder: (context, animation, _, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1.0, 0.0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
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
            'Sign Up',
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

/// Forgot password dialog
class _ForgotPasswordDialog extends StatefulWidget {
  final String email;

  const _ForgotPasswordDialog({required this.email});

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: Color(0xFF0097b2)),
          SizedBox(width: 8),
          Text(
            'Reset Password',
            style: TextStyle(
              color: Color(0xFF0e0259),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Text(
        'Send a password reset link to:\n${widget.email}',
        style: TextStyle(color: const Color(0xFF0e0259).withValues(alpha: 0.8)),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _sendResetEmail,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0097b2),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Send Link'),
        ),
      ],
    );
  }

  Future<void> _sendResetEmail() async {
    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: widget.email);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset link sent! Check your email.'),
            backgroundColor: Color(0xFF4ECDC4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_getResetErrorMessage(e.code)),
            backgroundColor: Colors.red[400],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getResetErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'invalid-email':
        return 'Invalid email address.';
      default:
        return 'Failed to send reset email. Please try again.';
    }
  }
}

/// Input validators
class _Validators {
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your university email';
    }
    if (!value.contains('@student.ksu.edu.sa')) {
      return 'Please use your KSU university email';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    return null;
  }
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