import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Small status pill: icon + short label. Used for connection,
/// sharing, conversion, and presence states.
class StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color background;

  const StatusChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
  });

  factory StatusChip.live() => const StatusChip(
        label: 'Live',
        icon: Icons.sensors,
        color: AppColors.success,
        background: AppColors.successBg,
      );

  factory StatusChip.connected() => const StatusChip(
        label: 'Connected',
        icon: Icons.wifi,
        color: AppColors.success,
        background: AppColors.successBg,
      );

  factory StatusChip.waiting() => const StatusChip(
        label: 'Waiting',
        icon: Icons.hourglass_bottom,
        color: AppColors.warning,
        background: AppColors.warningBg,
      );

  factory StatusChip.reconnecting() => const StatusChip(
        label: 'Reconnecting',
        icon: Icons.sync,
        color: AppColors.warning,
        background: AppColors.warningBg,
      );

  factory StatusChip.offline() => const StatusChip(
        label: 'Offline',
        icon: Icons.wifi_off,
        color: AppColors.error,
        background: AppColors.errorBg,
      );

  factory StatusChip.paused() => const StatusChip(
        label: 'Paused',
        icon: Icons.pause_circle_outline,
        color: AppColors.muted,
        background: AppColors.surfaceSoft,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Section heading with optional action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    )),
                if (subtitle != null)
                  Text(subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      )),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Numbered how-to step with an icon (network guide, onboarding).
class StepTile extends StatelessWidget {
  final int step;
  final IconData icon;
  final String title;
  final String subtitle;

  const StepTile({
    super.key,
    required this.step,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Step $step · $title',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
