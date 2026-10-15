import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
import '../widgets/motion.dart';

/// Splash: the logo settles in, then the app moves on.
///
/// Everything is finite — a looping animation here would keep the CPU awake
/// during the one moment the app has nothing to do.
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
    _timer = Timer(const Duration(milliseconds: 1400), _finish);
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finish,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        // The mark grows out of nothing, then the wordmark follows it:
                        // one gesture, so the screen feels composed rather than stacked.
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.86, end: 1),
                          duration: Motion.page,
                          curve: Curves.easeOutBack,
                          builder: (context, value, child) => Transform.scale(
                            scale: value,
                            child: Opacity(opacity: value.clamp(0, 1), child: child),
                          ),
                          child: const AppLogo(size: 88),
                        ),
                        FadeIn(
                          delay: Motion.stagger(2),
                          child: Column(
                            children: [
                              const SizedBox(height: 18),
                              Text(
                                'ClassCast',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'OFFLINE',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                  letterSpacing: 3,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Share. Present. Learn.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        // A determinate-looking sweep instead of an endless spinner:
                        // it finishes exactly as the app hands over to the role screen.
                        SizedBox(
                          width: 120,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 1250),
                            curve: Curves.easeInOutCubic,
                            builder: (context, value, _) => ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: value,
                                minHeight: 3,
                                backgroundColor: AppColors.primarySoft,
                                valueColor:
                                    const AlwaysStoppedAnimation(AppColors.primary),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Works without internet',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // The credit sits at the very bottom, and arrives last: a hairline
              // draws itself, then the name lifts in under it. Both are finite,
              // so the splash settles exactly as the app hands over.
              FadeIn(
                delay: Motion.stagger(6),
                rise: 10,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: Motion.standard,
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) => Opacity(
                          opacity: value.clamp(0, 1),
                          child: SizedBox(
                            width: 44 * value,
                            child: child,
                          ),
                        ),
                        child: Container(
                          height: 1,
                          color: AppColors.primarySoft,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'By MerjDev',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
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

