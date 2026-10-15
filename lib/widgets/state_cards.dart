import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'motion.dart';

/// Reusable empty / loading / error states with icon, short text, recovery.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FadeIn(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 30, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
                textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
          ),
        ),
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  final String message;

  const LoadingState({super.key, this.message = 'Loading…'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 12),
          Text(message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
              )),
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    this.icon = Icons.error_outline,
    required this.title,
    required this.message,
    this.retryLabel = 'Try again',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FadeIn(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child:
                  Icon(icon, size: 30, color: AppColors.error),
            ),
            const SizedBox(height: 12),
            Text(title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
                textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
                textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ],
          ),
        ),
      ),
    );
  }
}
