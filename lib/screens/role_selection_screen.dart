import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../widgets/app_logo.dart';

/// Role selection: Teacher / Student big icon cards + demo toggle.
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
      body: SafeArea(
        child: ContentWidth(
          maxWidth: 520,
          child: ListView(
            padding: EdgeInsets.all(context.pagePadding),
            children: [
              const SizedBox(height: 24),
              const Center(child: AppLogo(size: 72)),
              const SizedBox(height: 12),
              Text('ClassCast',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  )),
              Text('Offline',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.muted,
                    letterSpacing: 4,
                  )),
              const SizedBox(height: 8),
              Text('Choose your role',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.muted,
                  )),
              const SizedBox(height: 24),
              _RoleCard(
                icon: Icons.school,
                title: 'Teacher',
                subtitle: 'Host a classroom and present',
                onTap: onTeacher,
              ),
              const SizedBox(height: 12),
              _RoleCard(
                icon: Icons.person,
                title: 'Student',
                subtitle: 'Join with QR or session ID',
                onTap: onStudent,
              ),
              const SizedBox(height: 24),
              Text(
                'No internet needed. Connect to the teacher hotspot or local Wi-Fi.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon,
                    color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style:
                            theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        )),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
