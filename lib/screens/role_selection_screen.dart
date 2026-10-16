import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/motion.dart';
import '../utils/responsive.dart';
import '../widgets/ui_kit.dart';

/// Role selection: the two ways into the app, as the design draws them — one
/// filled, one soft, so the choice is obvious without reading it.
class RoleSelectionScreen extends StatelessWidget {
  final VoidCallback onTeacher;
  final VoidCallback onStudent;

  const RoleSelectionScreen({
    super.key,
    required this.onTeacher,
    required this.onStudent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 520,
          child: ListView(
            padding: EdgeInsets.all(context.pagePadding),
            children: [
              const SizedBox(height: 56),
              const FadeIn(
                child: Center(
                  child: AppBrandLockup(logoSize: 72, gap: 14),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'Choose your role',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 16),
              FadeIn(
                delay: Motion.stagger(1),
                child: _RoleCard(
                  icon: Icons.school_outlined,
                  label: 'Teacher',
                  selected: true,
                  onTap: onTeacher,
                ),
              ),
              const SizedBox(height: 12),
              FadeIn(
                delay: Motion.stagger(2),
                child: _RoleCard(
                  icon: Icons.person_outline,
                  label: 'Student',
                  onTap: onStudent,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'No internet needed. Connect to the teacher hotspot or local Wi-Fi.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// A full-width role button.
///
/// [selected] is the filled blue treatment for Teacher. The unselected state is
/// not an outline: an outline competes with the filled button, while a soft
/// tint reads instantly as "the other one".
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected ? Colors.white : AppColors.primary;
    final background = selected ? AppColors.primary : AppColors.primarySoft;

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ),
            // Decoration only: a tap handler here would fire the callback
            // twice and push the route twice.
            Icon(Icons.chevron_right, color: foreground, size: 22),
          ],
        ),
      ),
    );
  }
}