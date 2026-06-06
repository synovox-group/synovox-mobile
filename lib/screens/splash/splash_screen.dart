import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // Master controller — drives everything
  late final AnimationController _ctrl;

  // ── Logo ──────────────────────────────────────────────
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoShadow;

  // ── Rings (radio-wave effect) ─────────────────────────
  late final Animation<double> _ring1Scale;
  late final Animation<double> _ring1Opacity;
  late final Animation<double> _ring2Scale;
  late final Animation<double> _ring2Opacity;
  late final Animation<double> _ring3Scale;
  late final Animation<double> _ring3Opacity;

  // ── Text ──────────────────────────────────────────────
  late final Animation<Offset> _titleOffset;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _dotOpacity;

  // ── Exit ──────────────────────────────────────────────
  late final Animation<double> _exitOpacity;

  static const _primary = Color(0xFF2563EB);
  static const _totalMs = 6000;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _totalMs),
    );

    // ── Logo: spring scale ────────────────────────────────
    _logoScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.18, end: 0.94)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 15,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.94, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
    ]).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.45),
    ));

    _logoOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.15, curve: Curves.easeIn),
      ),
    );

    _logoShadow = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.1, 0.4, curve: Curves.easeOut),
      ),
    );

    // ── Rings ─────────────────────────────────────────────
    _ring1Scale = Tween(begin: 1.0, end: 2.5).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.12, 0.52, curve: Curves.easeOut),
      ),
    );
    _ring1Opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.45), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 0.45, end: 0.0), weight: 90),
    ]).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.12, 0.52),
    ));

    _ring2Scale = Tween(begin: 1.0, end: 3.2).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.18, 0.62, curve: Curves.easeOut),
      ),
    );
    _ring2Opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.30), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 0.30, end: 0.0), weight: 90),
    ]).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.18, 0.62),
    ));

    _ring3Scale = Tween(begin: 1.0, end: 4.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.24, 0.72, curve: Curves.easeOut),
      ),
    );
    _ring3Opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.15), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: 0.0), weight: 90),
    ]).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.24, 0.72),
    ));

    // ── Title ─────────────────────────────────────────────
    _titleOffset = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.38, 0.60, curve: Curves.easeOutCubic),
    ));

    _titleOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.38, 0.58),
      ),
    );

    _taglineOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.52, 0.70),
      ),
    );

    _dotOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.65, 0.80),
      ),
    );

    // ── Exit fade ─────────────────────────────────────────
    _exitOpacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.85, 1.0, curve: Curves.easeInCubic),
      ),
    );

    _ctrl.forward().then((_) {
      if (mounted) _navigate();
    });
  }

  void _navigate() {
    final token = ref.read(authProvider).token;
    context.go(token != null ? '/dashboard' : '/login');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Opacity(
          opacity: _exitOpacity.value,
          child: Scaffold(
            backgroundColor: Colors.white,
            body: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    const Color(0xFFEFF6FF).withOpacity(
                      (_logoOpacity.value * 0.8).clamp(0.0, 1.0),
                    ),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  // ── Contenu parfaitement centré ────────
                  // On équilibre top/bottom avec le max des deux safe areas
                  // pour que MainAxisAlignment.center soit au vrai milieu visuel.
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: topPad > bottomPad ? topPad : bottomPad,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // ── Logo + Rings ───────────────
                          SizedBox(
                            width: 220,
                            height: 220,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                _Ring(
                                  size: 96,
                                  scale: _ring3Scale.value,
                                  opacity: _ring3Opacity.value,
                                  color: _primary,
                                  strokeWidth: 1.0,
                                ),
                                _Ring(
                                  size: 96,
                                  scale: _ring2Scale.value,
                                  opacity: _ring2Opacity.value,
                                  color: _primary,
                                  strokeWidth: 1.5,
                                ),
                                _Ring(
                                  size: 96,
                                  scale: _ring1Scale.value,
                                  opacity: _ring1Opacity.value,
                                  color: _primary,
                                  strokeWidth: 2.0,
                                ),
                                Opacity(
                                  opacity: _logoOpacity.value,
                                  child: Transform.scale(
                                    scale: _logoScale.value,
                                    child: Container(
                                      width: 96,
                                      height: 96,
                                      decoration: BoxDecoration(
                                        color: _primary,
                                        borderRadius: BorderRadius.circular(28),
                                        boxShadow: [
                                          BoxShadow(
                                            color: _primary.withOpacity(
                                              0.45 * _logoShadow.value,
                                            ),
                                            blurRadius: 32,
                                            spreadRadius: 0,
                                            offset: const Offset(0, 12),
                                          ),
                                          BoxShadow(
                                            color: _primary.withOpacity(
                                              0.15 * _logoShadow.value,
                                            ),
                                            blurRadius: 60,
                                            spreadRadius: 4,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'S',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 52,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -1,
                                            height: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 28),

                          // ── Brand name ─────────────────
                          ClipRect(
                            child: SlideTransition(
                              position: _titleOffset,
                              child: FadeTransition(
                                opacity: _titleOpacity,
                                child: const Text(
                                  'Synovox',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -1.0,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // ── Tagline ────────────────────
                          FadeTransition(
                            opacity: _taglineOpacity,
                            child: const Text(
                              'Assistant téléphonique IA',
                              style: TextStyle(
                                fontSize: 15,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w400,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Dots épinglés en bas ───────────────
                  Positioned(
                    bottom: bottomPad + 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: FadeTransition(
                        opacity: _dotOpacity,
                        child: const _PulsingDots(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _Ring extends StatelessWidget {
  final double size, scale, opacity, strokeWidth;
  final Color color;

  const _Ring({
    required this.size,
    required this.scale,
    required this.opacity,
    required this.color,
    required this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: strokeWidth),
          ),
        ),
      ),
    );
  }
}

class _PulsingDots extends StatefulWidget {
  const _PulsingDots();

  @override
  State<_PulsingDots> createState() => _PulsingDotsState();
}

class _PulsingDotsState extends State<_PulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<Animation<double>> _scales;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    _scales = List.generate(3, (i) {
      final start = i * 0.2;
      return Tween(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, start + 0.5, curve: Curves.easeInOut),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Transform.scale(
              scale: _scales[i].value,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2563EB)
                      .withOpacity(0.3 + _scales[i].value * 0.7),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
