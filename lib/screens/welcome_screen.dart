import 'package:flutter/material.dart';
import 'signin_screen.dart';
import 'signup_screen.dart';

/// Welcome screen with beautiful Deep Sea themed design
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  // Deep Sea Color Palette
  static const _deepNavy = Color(0xFF0e0259);
  static const _oceanTeal = Color(0xFF006B7A);
  static const _brightTeal = Color(0xFF0097b2);
  static const _mintTeal = Color(0xFF4ECDC4);
  static const _lightMint = Color(0xFF95E1D3);
  static const _pureWhite = Color(0xFFFFFFFF);
  static const _softWhite = Color(0xFFF8FDFF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: _buildGradientBackground(),
        child: Stack(
          children: [
            const _BackgroundShapes(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Spacer(),
                    const _LogoSection(),
                    const SizedBox(height: 48),
                    const _WelcomeTextSection(),
                    const Spacer(flex: 2),
                    const _ActionButtonsSection(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Creates the ocean gradient background
  BoxDecoration _buildGradientBackground() {
    return const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _oceanTeal, // Deep ocean teal
          _brightTeal, // Bright teal
          _deepNavy, // Deep navy depths
        ],
        stops: [0.0, 0.6, 1.0],
      ),
    );
  }
}

//------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

/// Floating background decorative shapes
class _BackgroundShapes extends StatelessWidget {
  const _BackgroundShapes();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        // Top floating bubble
        _FloatingShape(
          top: -80,
          right: -60,
          size: 220,
          shape: BoxShape.circle,
          opacity: 0.08,
        ),
        // Bottom left wave shape
        _FloatingShape(
          bottom: -100,
          left: -50,
          size: 180,
          borderRadius: 40,
          opacity: 0.06,
        ),
        // Middle accent
        _FloatingShape(
          top: 180,
          right: -40,
          size: 120,
          shape: BoxShape.circle,
          opacity: 0.1,
        ),
        // Additional small bubble
        _FloatingShape(
          top: 350,
          left: -20,
          size: 80,
          shape: BoxShape.circle,
          opacity: 0.05,
        ),
      ],
    );
  }
}

//------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

/// Reusable floating shape widget
class _FloatingShape extends StatelessWidget {
  final double? top, bottom, left, right;
  final double size;
  final BoxShape? shape;
  final double? borderRadius;
  final double opacity;

  const _FloatingShape({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    this.shape,
    this.borderRadius,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: shape ?? BoxShape.rectangle,
          borderRadius: shape == null && borderRadius != null
              ? BorderRadius.circular(borderRadius!)
              : null,
          color: WelcomeScreen._pureWhite.withOpacity(opacity),
        ),
      ),
    );
  }
}

//------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

/// Enhanced logo section with glassmorphism effect
class _LogoSection extends StatelessWidget {
  const _LogoSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        color: WelcomeScreen._softWhite,
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          // Main shadow
          BoxShadow(
            color: WelcomeScreen._deepNavy.withOpacity(0.25),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
          // Highlight shadow
          BoxShadow(
            color: WelcomeScreen._pureWhite.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, -8),
          ),
        ],
        // Subtle border for glass effect
        border: Border.all(
          color: WelcomeScreen._pureWhite.withOpacity(0.2),
          width: 1.5,
        ),
      ),
        child: Center(
          child: Image.asset(
    'assets/images/logo.png', // path to your logo
    fit: BoxFit.contain,
  ),
),
    );
  }
}

class _WelcomeTextSection extends StatelessWidget {
  const _WelcomeTextSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Main welcome text with gradient effect
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, WelcomeScreen._softWhite],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(bounds),
          child: const Text(
            'أبشرك سهّلنا كل شي',
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Subtitle with glassmorphism container
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: WelcomeScreen._pureWhite.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: WelcomeScreen._pureWhite.withOpacity(0.2),
            ),
          ),
          child: Text(
            'Your academic companion for success',
            style: TextStyle(
              fontSize: 16,
              color: WelcomeScreen._pureWhite.withOpacity(0.9),
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

//------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

/// Action buttons section with enhanced styling
class _ActionButtonsSection extends StatelessWidget {
  const _ActionButtonsSection({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PrimaryButton(
          onPressed: () => _navigateToSignIn(context),
          icon: Icons.login_rounded,
          label: 'Sign In',
          backgroundColor: WelcomeScreen._softWhite,
          foregroundColor: WelcomeScreen._oceanTeal,
        ),
        const SizedBox(height: 18),
        _SecondaryButton(
          onPressed: () => _navigateToSignUp(context),
          icon: Icons.person_add_rounded,
          label: 'Create Account',
        ),
      ],
    );
  }

  void _navigateToSignIn(BuildContext context) {
    Navigator.push(
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
  }

  void _navigateToSignUp(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, _) => const SignUpScreen(),
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
}

//------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

/// Primary button with glassmorphism effect
class _PrimaryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _PrimaryButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

//------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

/// Secondary button with glass border effect
class _SecondaryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  const _SecondaryButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [
            WelcomeScreen._pureWhite.withOpacity(0.12),
            WelcomeScreen._pureWhite.withOpacity(0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: WelcomeScreen._pureWhite.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: WelcomeScreen._deepNavy.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: WelcomeScreen._pureWhite.withOpacity(0.95),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: WelcomeScreen._pureWhite.withOpacity(0.95),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
