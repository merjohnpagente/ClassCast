import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';

/// Splash: logo, name, tagline, short load, then auto-navigate.
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
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 88),
                const SizedBox(height: 16),
                Text('ClassCast',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    )),
                Text('Offline',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                      letterSpacing: 4,
                    )),
                const SizedBox(height: 8),
                Text('Share. Present. Learn.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    )),
                const SizedBox(height: 28),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 16),
                Text('v1.0.0 · works offline',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
