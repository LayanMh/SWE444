import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'welcome_screen.dart';
import 'signin_screen.dart';
import 'signup_screen.dart'; // Add this import

class EmailVerificationScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;
  
  const EmailVerificationScreen({
    super.key,
    this.userData,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late Timer _timer;

  bool _canResend = false; // Controls whether user can resend - start disabled
  Timer? _resendCooldownTimer; // Timer to re-enable resend button
  Timer? _countdownTimer; // Timer for countdown display
  int _countdown = 60; // Countdown seconds remaining - start at 60

  @override
  void initState() {
    super.initState();
    
    // Start cooldown immediately when screen loads
    _startCooldown();
    
    // Start a timer to check verification status every 3 seconds
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final user = _auth.currentUser;
      if (user != null) {
        await user.reload();
        if (user.emailVerified) {
          timer.cancel();
          debugPrint("User email verified!");
          
          // Save user data to Firestore now that email is verified
          if (widget.userData != null) {
            await _saveUserDataToFirestore(user.uid, widget.userData!);
          }
          
          if (mounted) {
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account created successfully! You can now sign in.'),
                backgroundColor: Color(0xFF4ECDC4),
                duration: Duration(seconds: 3),
              ),
            );
            
            // Navigate to Sign In page instead of Welcome page
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const SignInScreen()),
              (route) => false,
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _resendCooldownTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _saveUserDataToFirestore(String uid, Map<String, dynamic> userData) async {
    try {
      debugPrint("Saving verified user data for UID: $uid");
      
      final userDoc = _firestore.collection('users').doc(uid);
      
      await userDoc.set({
        ...userData,
        'createdAt': FieldValue.serverTimestamp(),
        'emailVerified': true,
        'accountStatus': 'active',
      });
      
      debugPrint("User data saved successfully to Firestore after verification");
    } catch (e) {
      debugPrint("Error saving user data: $e");
      // Show error to user but don't block the flow
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Account verified but failed to save profile. Please contact support.'),
            backgroundColor: Colors.orange[600],
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _startCooldown() {
    setState(() {
      _canResend = false;
      _countdown = 60; // 60 seconds cooldown
    });

    // Start countdown timer that updates every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _countdown--;
          if (_countdown <= 0) {
            _canResend = true;
            timer.cancel();
          }
        });
      }
    });

    // Backup timer to ensure button is re-enabled after 60 seconds
    _resendCooldownTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) {
        setState(() {
          _canResend = true;
          _countdown = 0;
        });
      }
    });
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResend) return; // Exit if cooldown active

    final user = _auth.currentUser;
    if (user != null) {
      try {
        debugPrint('Attempting to send verification email to: ${user.email}');
        await user.sendEmailVerification();
        debugPrint('Verification email sent successfully');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification email resent! Please check your email.'),
              backgroundColor: Color(0xFF4ECDC4),
              duration: Duration(seconds: 4),
            ),
          );
        }

        // Start the cooldown with countdown display
        _startCooldown();

      } catch (e) {
        debugPrint('Error resending email: $e');
        if (mounted) {
          String errorMessage = 'Failed to resend email. Please try again later.';
          
          // Handle specific Firebase errors
          if (e.toString().contains('too-many-requests')) {
            errorMessage = 'Too many requests. Please wait before trying again.';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red[400],
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } else {
      debugPrint('ERROR: No current user found');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Session expired. Please sign in again.'),
            backgroundColor: Colors.red[400],
          ),
        );
      }
    }
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
                  child: _VerificationCard(
                    onResend: _canResend ? _resendVerificationEmail : null,
                    countdown: _countdown,
                    canResend: _canResend,
                    hasUserData: widget.userData != null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
              onPressed: () async {
                // Delete the Firebase Auth user since they're abandoning verification
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  try {
                    debugPrint('Deleting unverified user: ${user.email}');
                    await user.delete();
                    debugPrint('Unverified user deleted successfully');
                  } catch (e) {
                    debugPrint('Error deleting unverified user: $e');
                  }
                }
                
                // Sign out to clear any remaining session
                await FirebaseAuth.instance.signOut();
                
                // Navigate back to signup page
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const SignUpScreen()),
                    (route) => false,
                  );
                }
              },
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
            ),
          ),
          const Expanded(
            child: Text(
              'Verify Email',
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

class _VerificationCard extends StatelessWidget {
  final VoidCallback? onResend;
  final int countdown;
  final bool canResend;
  final bool hasUserData;

  const _VerificationCard({
    this.onResend,
    required this.countdown,
    required this.canResend,
    required this.hasUserData,
  });

  String _formatCountdown(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${remainingSeconds}s';
    }
    return '${remainingSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 100),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Header(),
            const SizedBox(height: 24),
            const Icon(Icons.email_outlined, size: 80, color: Color(0xFF0097b2)),
            const SizedBox(height: 24),
            Text(
              hasUserData 
                ? 'Please check your university email to complete your registration.'
                : 'Please check your university email to verify your account.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0e0259)),
            ),
            const SizedBox(height: 12),
            Text(
              'A verification link has been sent to your email address: \n${FirebaseAuth.instance.currentUser?.email ?? 'N/A'}.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: const Color(0xFF0e0259).withOpacity(0.7), fontWeight: FontWeight.w500),
            ),
            if (hasUserData) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF4ECDC4).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.security_outlined,
                      size: 20,
                      color: const Color(0xFF0097b2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your account data will only be saved after email verification is complete.',
                        style: TextStyle(
                          fontSize: 13,
                          color: const Color(0xFF0097b2),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Timer text display
            if (!canResend)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0097b2).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF0097b2).withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: const Color(0xFF0097b2),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      countdown > 0 
                        ? 'Wait ${_formatCountdown(countdown)} to resend'
                        : 'You can now resend the email',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF0097b2),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            _ResendButton(
              onPressed: onResend,
              canResend: canResend,
            ),
          ],
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
            gradient: const LinearGradient(colors: [Color(0xFF0097b2), Color(0xFF006B7A), Color(0xFF0e0259)]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: const Color(0xFF0097b2).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset('assets/images/logo.png', width: 64, height: 64, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Email Verification',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0e0259), letterSpacing: -0.5),
        ),
      ],
    );
  }
}

class _ResendButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool canResend;

  const _ResendButton({
    this.onPressed,
    required this.canResend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: canResend 
            ? [const Color(0xFF0097b2), const Color(0xFF006B7A)]
            : [Colors.grey.shade400, Colors.grey.shade500],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: canResend 
          ? [BoxShadow(color: const Color(0xFF0097b2).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]
          : [],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              canResend ? Icons.refresh : Icons.block,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              canResend 
                ? 'Resend Verification Email'
                : 'Resend Disabled',
              style: const TextStyle(
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