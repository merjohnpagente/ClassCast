import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/participant.dart';
import '../../providers/app_state.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../../utils/responsive.dart';
import '../../widgets/state_cards.dart';

/// Connected students: total, list, status, device, join time,
/// refresh, remove (teacher only).
class StudentsScreen extends StatelessWidget {
  const StudentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = context.watch<SessionProvider>();
    final app = context.watch<AppState>();
    final items = sessions.participants;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected Students'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                sessions.load(demoMode: app.demoMode),
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: 640,
        child: ListView(
          padding: EdgeInsets.all(context.pagePadding),
          children: [
            Text('${sessions.connectedCount} Online',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                )),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const EmptyState(
                icon: Icons.people_outline,
                title: 'No connected students',
                subtitle:
                    'Share the QR code or joining address to invite students.',
              )
            else
              for (final p in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _StudentRow(
                    participant: p,
                    onRemove: () =>
                        sessions.removeParticipant(p.id),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  final Participant participant;
  final VoidCallback onRemove;

  const _StudentRow({
    required this.participant,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected =
        participant.status == Presence.connected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(21),
              ),
              child: const Icon(Icons.person,
                  color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(participant.name,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      )),
                  Text(
                    '${participant.deviceType} · Joined ${formatTime(participant.joinedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected
                      ? 'Connected'
                      : participant.status ==
                              Presence.reconnecting
                          ? 'Reconnecting'
                          : 'Left',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: connected
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.person_remove_outlined,
                  size: 20, color: AppColors.muted),
              onPressed: () => _confirmRemove(context),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove participant?'),
        content:
            Text('${participant.name} will leave the session.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onRemove();
            },
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
