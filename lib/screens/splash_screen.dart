import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/motion.dart';
import '../widgets/ui_kit.dart';

/// How long the splash stays up, and how long the progress bar takes to
/// cross. They are deliberately the same length: the bar finishes exactly as
/// the app hands over, so the wait reads as the bar filling rather than as
/// the bar filling and then something else happening.
static const _duration = Duration(milliseconds: 4000);

/// Splash: the mark settles in on a full-bleed blue field, then the app moves
/// on.
///
/// Everything is finite — a looping animation here would keep the CPU awake
/// during the one moment the app has nothing to do. Tapping anywhere skips
/// straight to the role screen, so the four seconds are never in the way.
class SplashScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Wait for the splash to have actually been painted, then hold it long
    // enough to read. A plain Timer from initState fires on wall-clock time: on
    // a slow cold start it lands before the first frame, so the splash is
    // never seen, or lands between frames and flashes for one frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hold();
    });
  }

  void _hold() {
    if (_done) return;
    _timer = Timer(_duration, _finish);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The blue field: a single diagonal gradient rather than a flat
            // fill, which is what stops a full-screen brand colour from
            // looking like a stuck loading state.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDark],
                ),
              ),
            ),
            // The wave closes the bottom edge; without it the screen is just a
            // rectangle of blue.
            const Align(
              alignment: Alignment.bottomCenter,
              child: SoftWave(
                color: Color(0xFF6E8AFB),
                flipped: true,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(),
                    // The mark grows out of nothing, then the wordmark follows:
                    // one gesture, so the screen feels composed, not stacked.
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.86, end: 1),
                      duration: Motion.page,
                      curve: Curves.easeOutBack,
                      builder: (context, value, child) => Transform.scale(
                        scale: value,
                        child: Opacity(
                          opacity: value.clamp(0, 1),
                          child: child,
                        ),
                      ),
                      child: const AppBrandLockup(
                        logoSize: 96,
                        title: 'ClassCast',
                        subtitle: 'Offline',
                        onBlue: true,
                        gap: 20,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FadeIn(
                      delay: Motion.stagger(2),
                      rise: 8,
                      child: const Text(
                        'Share • Present • Learn',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const Spacer(),
                    FadeIn(
                      delay: Motion.stagger(5),
                      rise: 10,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
// A determinate sweep rather than an endless spinner: it
                              // fills across the same four seconds the screen is
                              // up, and finishes exactly as the app hands over.
                              SizedBox(
                                width: 110,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(begin: 0, end: 1),
                                  duration: _duration,
                                  curve: Curves.easeInOutCubic,
                              builder: (context, value, _) => ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: value,
                                  minHeight: 3,
                                  backgroundColor: Colors.white24,
                                  valueColor:
                                      const AlwaysStoppedAnimation(Colors.white),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Works without internet',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 14),
                          // The credit sits last, at the very bottom of the
                          // blue field, where it belongs: it is not something
                          // the teacher has to read to start a class.
                          const Text(
                            'By MerjDev',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}