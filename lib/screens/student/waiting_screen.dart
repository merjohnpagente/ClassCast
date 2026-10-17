import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/sync_provider.dart';
import '../../services/classcast_client.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui_kit.dart';
import '../../widgets/status_bits.dart';

/// Waiting room: shown after join until the teacher shares a document.
/// Auto-advances when the viewer becomes available (handled by shell).
class StudentWaitingScreen extends StatelessWidget {
  final VoidCallback onLeave;

  const StudentWaitingScreen({super.key, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sync = context.watch<SyncProvider>();
    final name =
        sync.snapshot?.name ?? 'Classroom ${sync.sessionId}';

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(context.pagePadding),
        child: ContentWidth(
          maxWidth: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppBrandLockup(logoSize: 64, gap: 14),
              const SizedBox(height: 28),
              Text(
                'Joining Session…',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 20),
              Text(
                'Please wait while the teacher starts the presentation.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 20),
              // The link state is kept because "am I connected?" is the first
              // thing a student wonders, but it sits under the explanation
              // instead of interrupting it.
              if (sync.link == LinkState.reconnecting)
                StatusChip.reconnecting()
              else if (sync.link == LinkState.live)
                StatusChip.waiting()
              else
                StatusChip.offline(),
              if (sync.link == LinkState.reconnecting) ...[
                const SizedBox(height: 12),
                Text(
                  'Still trying to reach the teacher. If this does not '
                  'recover, the Wi-Fi may be blocking phones from seeing '
                  'each other — ask the teacher to switch on a hotspot.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  await sync.leave();
                  onLeave();
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Leave'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
