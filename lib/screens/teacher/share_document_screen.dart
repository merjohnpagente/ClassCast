import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/doc_types.dart';
import '../../models/shared_document.dart';
import '../../providers/session_provider.dart';
import '../../services/document_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../../utils/responsive.dart';
import '../../widgets/document_card.dart';
import '../../widgets/status_bits.dart';
import 'presentation_screen.dart';

/// Share screen: preview, name/type/page, share button, replace,
/// sharing + conversion status.
class ShareDocumentScreen extends StatelessWidget {
  final SharedDocument doc;

  const ShareDocumentScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = context.watch<SessionProvider>();
    final active = sessions.active;
    final notice = DocumentService.conversionNotice(doc);

    return Scaffold(
      appBar: AppBar(title: const Text('Share Document')),
      body: ContentWidth(
        maxWidth: 720,
        child: ListView(
          padding: EdgeInsets.all(context.pagePadding),
          children: [
            _previewBox(context, theme),
            const SizedBox(height: 12),
            Text('${doc.name}.${doc.extension}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                )),
            Text(
              '${doc.kind.name.toUpperCase()} · ${doc.sizeBytes > 0 ? formatBytes(doc.sizeBytes) : '—'}'
              '${doc.pageCount > 0 ? ' · ${doc.pageCount} pages' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
            if (notice != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: doc.status == DocStatus.ready
                      ? AppColors.successBg
                      : AppColors.warningBg,
                  borderRadius:
                      BorderRadius.circular(AppRadius.card),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      doc.status == DocStatus.ready
                          ? Icons.check_circle_outline
                          : Icons.sync,
                      color: doc.status == DocStatus.ready
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(notice,
                          style:
                              theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (active == null)
              const ErrorHint(
                  message:
                      'No active session. Create a session first, then share.'),
            FilledButton.icon(
              onPressed: active == null
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final nav = Navigator.of(context);
                      // The host can refuse — the file may have been cleared
                      // from the phone, or the session may have ended. Saying
                      // nothing left the teacher believing everyone had it.
                      final ok = await sessions.shareDocument(doc);
                      if (!ok) {
                        messenger.showSnackBar(const SnackBar(
                          content: Text(
                              'The students could not be sent this file. Check '
                              'that the session is still running and the file '
                              'is still on this device.'),
                        ));
                        return;
                      }
                      nav.push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const TeacherPresentationScreen()),
                      );
                    },
              icon: const Icon(Icons.cast_connected),
              label: const Text('Share to Active Session'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Replace'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: active?.documentId == doc.id
                        ? () => sessions.clearDocument()
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Unshare'),
                  ),
                ),
              ],
            ),
            if (active?.documentId == doc.id) ...[
              const SizedBox(height: 8),
              const StatusChip(
                  label: 'Sharing now',
                  icon: Icons.sensors,
                  color: AppColors.success,
                  background: AppColors.successBg),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewBox(BuildContext context, ThemeData theme) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(color: AppColors.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileTypeIcon(
                kind: doc.kind,
                extension: doc.extension,
                size: 64),
            const SizedBox(height: 8),
            Text(
              doc.pageCount > 0
                  ? 'Page ${doc.currentPage} / ${doc.pageCount}'
                  : 'Preview',
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

class ErrorHint extends StatelessWidget {
  final String message;
  const ErrorHint({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
