import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/sync_provider.dart';
import '../../services/classcast_client.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_logo.dart';
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
      child: ContentWidth(
        maxWidth: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 64),
            const SizedBox(height: 12),
            Text('Joining Session…',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                )),
            const SizedBox(height: 4),
            Text(name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted,
                )),
            const SizedBox(height: 12),
            if (sync.link == LinkState.reconnecting)
              StatusChip.reconnecting()
            else if (sync.link == LinkState.live)
              StatusChip.waiting()
            else
              StatusChip.offline(),
            const SizedBox(height: 12),
            Text('Please wait while the teacher starts the presentation.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                )),
            const SizedBox(height: 20),
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () async {
                await sync.leave();
                onLeave();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Leave Session'),
            ),
          ],
        ),
      ),
    );
  }
}
