import 'package:flutter/material.dart';
import 'signin_screen.dart';
import 'signup_screen.dart';
import 'package:video_player/video_player.dart';

/// Welcome screen with beautiful Deep Sea themed design
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  // GPA Calculator palette
  static const _deepNavy = Color(0xFF0D4F94);
  static const _brightTeal = Color(0xFF4A98E9);
  static const _oceanTeal = Color(0xFFE6F3FF);
  static const _pureWhite = Color(0xFFFFFFFF);
  static const _softWhite = Color(0xFFF2FAFF);

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
                    const _VideoHero(),
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
          _deepNavy,
          _brightTeal,
          _oceanTeal,
        ],
        stops: [0.0, 0.55, 1.0],
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
class _VideoHero extends StatefulWidget {
  const _VideoHero();

  @override
  State<_VideoHero> createState() => _VideoHeroState();
}

class _VideoHeroState extends State<_VideoHero> {
  late final VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/images/welcome.mp4')
      ..setLooping(true)
      ..setVolume(0);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      _controller.play();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        color: WelcomeScreen._softWhite,
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: WelcomeScreen._deepNavy.withOpacity(0.25),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: WelcomeScreen._pureWhite.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, -8),
          ),
        ],
        border: Border.all(
          color: WelcomeScreen._brightTeal.withOpacity(0.25),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_initialized)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              )
            else
              const Center(child: CircularProgressIndicator()),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    WelcomeScreen._deepNavy.withOpacity(0.1),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
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
            'أبشرك سهّلنا كل شيء',
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
      ],
    );
  }
}

class _ActionButtonsSection extends StatelessWidget {
  const _ActionButtonsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SecondaryButton(
          onPressed: () => _navigateToSignIn(context),
          icon: Icons.login_rounded,
          label: 'Sign In',
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
            position:
                Tween<Offset>(
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
  }

  void _navigateToSignUp(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, _) => const SignUpScreen(),
        transitionsBuilder: (context, animation, _, child) {
          return SlideTransition(
            position:
                Tween<Offset>(
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
  }
}

//------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

/// Secondary button with glass border effect
class _SecondaryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  const _SecondaryButton({
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
            WelcomeScreen._brightTeal,
            WelcomeScreen._deepNavy,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: WelcomeScreen._brightTeal.withOpacity(0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: WelcomeScreen._deepNavy.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
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
                color: WelcomeScreen._pureWhite,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
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
