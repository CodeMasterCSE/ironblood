import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'auth_screen.dart';
import 'admin_screen.dart';
import 'member_screen.dart';
import 'trainer_screen.dart';
import 'services/session_service.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback? onAnimationComplete;

  const SplashScreen({super.key, this.onAnimationComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Primary Color Palette
  static const Color primaryGold = Color(0xFFC9A227);
  static const Color primaryGreen = Color(0xFF123222);
  static const Color darkBackground = Color(0xFF091911);
  static const Color deepGold = Color(0xFF9E7B1A);
  static const Color lightGold = Color(0xFFFFE082);

  // Animation Controllers
  late AnimationController _mainController;
  late AnimationController _pulseController;
  late AnimationController _rotationController;

  // Curved Animations
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoOpacityAnimation;
  late Animation<double> _ringScaleAnimation;
  late Animation<double> _titleSlideAnimation;
  late Animation<double> _titleOpacityAnimation;
  late Animation<double> _subtitleOpacityAnimation;
  late Animation<double> _taglineSlideAnimation;
  late Animation<double> _taglineOpacityAnimation;
  late Animation<double> _glowAnimation;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    // 1. Main entrance controller
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    // 2. Ambient breathing pulse controller
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // 3. Ambient slow rotating ring controller
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();

    // Staggered Entrance Animations
    _logoScaleAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.50, curve: Curves.easeOutBack),
      ),
    );

    _logoOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.35, curve: Curves.easeIn),
      ),
    );

    _ringScaleAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.08, 0.55, curve: Curves.easeOutCubic),
      ),
    );

    // Title Entrance
    _titleSlideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    _titleOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.35, 0.60, curve: Curves.easeIn),
      ),
    );

    // Subtitle Entrance
    _subtitleOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.50, 0.75, curve: Curves.easeIn),
      ),
    );

    // Tagline Entrance
    _taglineSlideAnimation = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.60, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _taglineOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.60, 0.80, curve: Curves.easeIn),
      ),
    );

    // Ambient Breathing Glow
    _glowAnimation = Tween<double>(begin: 0.75, end: 1.25).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );

    _mainController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (widget.onAnimationComplete != null) {
          widget.onAnimationComplete!();
        } else {
          _navigateToNextScreen();
        }
      }
    });

    _mainController.forward();
  }

  void _navigateToNextScreen() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    final role = await SessionService.getUserRole();

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    Widget targetScreen;
    if (role == 'admin') {
      targetScreen = const AdminScreen();
    } else if (role == 'trainer') {
      targetScreen = const TrainerScreen();
    } else if (role == 'member') {
      targetScreen = const MemberScreen();
    } else {
      targetScreen = const AuthScreen();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 800),
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fadeAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOutCubic,
          );
          return FadeTransition(
            opacity: fadeAnimation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _navigateToNextScreen,
        child: Stack(
          children: [
          // 1. Layered Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, -0.15),
                  radius: 1.15,
                  colors: [
                    primaryGreen,
                    Color(0xFF0C2217),
                    darkBackground,
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          // 2. Animated Particle Aura Effect
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _rotationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: ParticleAtmospherePainter(
                    animationValue: _rotationController.value,
                    primaryColor: primaryGold,
                  ),
                );
              },
            ),
          ),

          // 3. Subtle Ambient Light Radial Flare behind logo
          Center(
            child: AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _glowAnimation.value,
                  child: Container(
                    width: 360,
                    height: 360,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          primaryGold.withValues(alpha: 0.22),
                          primaryGreen.withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 4. Main Centered Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Centerpiece: Logo + Geometric Halo Rings
                    SizedBox(
                      width: 280,
                      height: 280,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Rotating outer gold accent ring with gym ticks
                          AnimatedBuilder(
                            animation: Listenable.merge(
                                [_rotationController, _ringScaleAnimation]),
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _ringScaleAnimation.value,
                                child: Transform.rotate(
                                  angle: _rotationController.value *
                                      2 *
                                      math.pi,
                                  child: CustomPaint(
                                    size: const Size(270, 270),
                                    painter: GoldRingPainter(
                                      goldColor: primaryGold,
                                      pulseOpacity: _glowAnimation.value * 0.7,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          // Counter-rotating inner subtle accent ring
                          AnimatedBuilder(
                            animation: Listenable.merge(
                                [_rotationController, _ringScaleAnimation]),
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _ringScaleAnimation.value * 0.94,
                                child: Transform.rotate(
                                  angle: -_rotationController.value *
                                      2 *
                                      math.pi *
                                      0.6,
                                  child: CustomPaint(
                                    size: const Size(225, 225),
                                    painter: InnerRingPainter(
                                      goldColor: lightGold,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          // Logo (Rendered directly with transparent backdrop)
                          AnimatedBuilder(
                            animation: Listenable.merge(
                                [_logoScaleAnimation, _logoOpacityAnimation]),
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _logoScaleAnimation.value,
                                child: Opacity(
                                  opacity: _logoOpacityAnimation.value,
                                  child: SizedBox(
                                    width: 190,
                                    height: 190,
                                    child: Image.asset(
                                      'lib/logo.png',
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return const Icon(
                                          Icons.fitness_center_rounded,
                                          size: 90,
                                          color: primaryGold,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 38),

                    // Title: "IRONBLOOD"
                    AnimatedBuilder(
                      animation: Listenable.merge(
                          [_titleSlideAnimation, _titleOpacityAnimation]),
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _titleSlideAnimation.value),
                          child: Opacity(
                            opacity: _titleOpacityAnimation.value,
                            child: ShaderMask(
                              shaderCallback: (bounds) {
                                return const LinearGradient(
                                  colors: [
                                    lightGold,
                                    primaryGold,
                                    deepGold,
                                    lightGold,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ).createShader(bounds);
                              },
                              child: Text(
                                "IRONBLOOD",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.montserrat(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 8.5,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 2),

                    // Subtitle: "MUSCLE AND FITNESS STUDIO"
                    AnimatedBuilder(
                      animation: _subtitleOpacityAnimation,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _subtitleOpacityAnimation.value,
                          child: Text(
                            "MUSCLE AND FITNESS STUDIO",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.rajdhani(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 4.5,
                              color: const Color(0xFFE8D7A3),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Tagline Badge: "NO PAIN NO GAIN"
                    AnimatedBuilder(
                      animation: Listenable.merge(
                          [_taglineSlideAnimation, _taglineOpacityAnimation]),
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _taglineSlideAnimation.value),
                          child: Opacity(
                            opacity: _taglineOpacityAnimation.value,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: primaryGreen.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: primaryGold.withValues(alpha: 0.45),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryGold.withValues(alpha: 0.15),
                                    blurRadius: 14,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: primaryGold,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    "NO PAIN NO GAIN",
                                    style: GoogleFonts.rajdhani(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 3.5,
                                      color: lightGold,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: primaryGold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Custom painter to draw geometric gold orbit ring with tick marks
class GoldRingPainter extends CustomPainter {
  final Color goldColor;
  final double pulseOpacity;

  GoldRingPainter({
    required this.goldColor,
    required this.pulseOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Thin outer ring
    final circlePaint = Paint()
      ..color = goldColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius, circlePaint);

    // Glowing arc segments
    final arcPaint = Paint()
      ..color =
          goldColor.withValues(alpha: (0.75 * pulseOpacity).clamp(0.2, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;

    const segmentAngle = math.pi / 3;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      segmentAngle,
      false,
      arcPaint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      segmentAngle,
      false,
      arcPaint,
    );

    // Gym tick markers
    final tickPaint = Paint()
      ..color = goldColor.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;

    const totalTicks = 24;
    for (int i = 0; i < totalTicks; i++) {
      final angle = (i * 2 * math.pi) / totalTicks;
      final isMajor = i % 6 == 0;
      final tickLength = isMajor ? 8.0 : 4.0;

      final startX = center.dx + (radius - 1) * math.cos(angle);
      final startY = center.dy + (radius - 1) * math.sin(angle);
      final endX = center.dx + (radius - 1 - tickLength) * math.cos(angle);
      final endY = center.dy + (radius - 1 - tickLength) * math.sin(angle);

      canvas.drawLine(
        Offset(startX, startY),
        Offset(endX, endY),
        tickPaint..strokeWidth = isMajor ? 2.0 : 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GoldRingPainter oldDelegate) {
    return oldDelegate.pulseOpacity != pulseOpacity;
  }
}

/// Custom painter for inner counter-rotating ring
class InnerRingPainter extends CustomPainter {
  final Color goldColor;

  InnerRingPainter({required this.goldColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final dashPaint = Paint()
      ..color = goldColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const totalDashes = 12;
    for (int i = 0; i < totalDashes; i++) {
      if (i % 2 == 0) {
        final startAngle = (i * 2 * math.pi) / totalDashes;
        const sweepAngle = (math.pi * 2) / (totalDashes * 2);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepAngle,
          false,
          dashPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Dynamic particle atmosphere effect in background
class ParticleAtmospherePainter extends CustomPainter {
  final double animationValue;
  final Color primaryColor;

  ParticleAtmospherePainter({
    required this.animationValue,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final particlePaint = Paint()..style = PaintingStyle.fill;

    // Deterministic particle points
    const count = 30;
    for (int i = 0; i < count; i++) {
      final seedX = (math.sin(i * 99.0) * 0.5 + 0.5);
      final seedY = (math.cos(i * 33.0) * 0.5 + 0.5);
      final speed = 0.3 + (i % 5) * 0.15;
      final radius = 1.0 + (i % 4) * 0.8;

      final animatedY = (seedY - (animationValue * speed)) % 1.0;
      final x = seedX * size.width;
      final y = animatedY * size.height;

      final opacity =
          (math.sin((animationValue + i) * math.pi * 2) * 0.25 + 0.35)
              .clamp(0.08, 0.6);

      particlePaint.color = primaryColor.withValues(alpha: opacity);
      canvas.drawCircle(Offset(x, y), radius, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticleAtmospherePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
