import 'package:flutter/material.dart';

import '../models/classroom_session.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// Active / recent classroom session card with icon + concise labels.
class SessionCard extends StatelessWidget {
  final ClassroomSession session;
  final int connectedCount;
  final VoidCallback? onTap;
  final VoidCallback? onEnd;
  final VoidCallback? onQr;

  const SessionCard({
    super.key,
    required this.session,
    this.connectedCount = 0,
    this.onTap,
    this.onEnd,
    this.onQr,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.meeting_room,
                        color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(session.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            )),
                        Text(
                          session.subject.isEmpty
                              ? formatDateTime(
                                  session.createdAt)
                              : '${session.subject} · ${formatDateTime(session.createdAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _liveDot(session.isActive),
                ],
              ),
              if (session.isActive) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _miniStat(Icons.people,
                        '$connectedCount connected'),
                    if (session.documentName != null)
                      _miniStat(Icons.description,
                          session.documentName!),
                    _miniStat(Icons.tag, session.id),
                  ],
                ),
              ],
              if (onEnd != null || onQr != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (onQr != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onQr,
                          icon: const Icon(
                              Icons.qr_code_2,
                              size: 18),
                          label: const Text('QR Code'),
                        ),
                      ),
                    if (onQr != null && onEnd != null)
                      const SizedBox(width: 8),
                    if (onEnd != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEnd,
                          icon: const Icon(Icons.stop,
                              size: 18),
                          label: const Text('End'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor:
                                AppColors.error,
                            side: const BorderSide(
                                color: AppColors.error),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveDot(bool active) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.success : AppColors.muted,
      ),
    );
  }

  Widget _miniStat(IconData icon, String label) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.muted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.inkSecondary,
                )),
          ),
        ],
      ),
    );
  }
}
