import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/participant.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../../utils/responsive.dart';
import '../../widgets/state_cards.dart';
import '../../widgets/ui_kit.dart';

/// Connected students: total, list, status, device, join time,
/// refresh, remove (teacher only).
class StudentsScreen extends StatelessWidget {
  const StudentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = context.watch<SessionProvider>();
    final items = sessions.participants;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Connected Students'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => sessions.load(),
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: 560,
        child: items.isEmpty
            ? ListView(
                padding: EdgeInsets.only(top: context.pagePadding),
                children: const [
                  EmptyState(
                    icon: Icons.people_outline,
                    title: 'No students yet',
                    subtitle: 'Show the QR code — students join by scanning it.',
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  AppSectionTitle('${sessions.connectedCount} Online'),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _StudentRow(
                            participant: items[i],
                            onRemove: () =>
                                sessions.removeParticipant(items[i].id),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Raise a hand from the student screen and it appears here '
                    'straight away.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
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
    final connected = participant.status == Presence.connected;
    // The design shows one dot. "Reconnecting" and "Left" used to share the
    // same colour *and* be told apart by an 11px caption, so two different
    // states looked identical at a glance — and the caption failed contrast
    // while doing it.
    final live = participant.status == Presence.reconnecting;

    return AppListRow(
      icon: Icons.person_outline,
      title: participant.name,
      subtitle: '${participant.deviceType} · '
          'Joined ${formatTime(participant.joinedAt)}',
      circularIcon: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LiveDot(
            active: connected,
            activeColor: live ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(width: 6),
          Text(
            connected
                ? 'Connected'
                : live
                    ? 'Reconnecting'
                    : 'Left',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: connected
                  ? AppColors.success
                  : live
                      ? AppColors.warning
                      : AppColors.muted,
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.person_remove_outlined,
                size: 20, color: AppColors.muted),
            onPressed: () => _confirmRemove(context),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove participant?'),
        content: Text('${participant.name} will leave the session.'),
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