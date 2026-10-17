import 'package:flutter/material.dart';

import '../models/doc_types.dart';
import '../models/shared_document.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// File-type badge: distinct icon + extension label.
/// Never relies on color alone to distinguish formats.
class FileTypeIcon extends StatelessWidget {
  final DocKind kind;
  final String extension;
  final double size;

  const FileTypeIcon({
    super.key,
    required this.kind,
    required this.extension,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color, bg) = _visual(kind);
    // The label was sized as a fraction of the tile, which put it at 7px in a
    // 44px tile — a grey smudge, and unreadable at arm's length in a
    // classroom. It is floored at a size that can actually be read. The tile
    // also carries a format-specific icon (a PDF sheet, a slide, a table), so
    // the format is never signalled by the text alone.
    final labelSize = size * 0.16 < 10 ? 10.0 : size * 0.16;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: size * 0.40, color: color),
          const SizedBox(height: 1),
          Text(
            extension.isEmpty ? 'FILE' : extension.toUpperCase(),
            maxLines: 1,
            style: TextStyle(
              fontSize: labelSize,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, Color, Color) _visual(DocKind kind) {
    switch (kind) {
      case DocKind.pdf:
        return (
          Icons.picture_as_pdf,
          AppColors.pdf,
          AppColors.pdf.withValues(alpha: 0.14)
        );
      case DocKind.powerpoint:
        return (
          Icons.slideshow,
          AppColors.ppt,
          AppColors.ppt.withValues(alpha: 0.14)
        );
      case DocKind.word:
        return (
          Icons.description,
          AppColors.word,
          AppColors.infoBg
        );
      case DocKind.excel:
        return (
          Icons.table_chart,
          AppColors.excel,
          AppColors.successBg
        );
      case DocKind.image:
        return (
          Icons.image,
          AppColors.image,
          AppColors.secondarySoft
        );
      case DocKind.text:
        return (
          Icons.text_snippet,
          AppColors.text,
          AppColors.surfaceSoft
        );
      case DocKind.video:
        return (
          Icons.play_circle_outline,
          AppColors.video,
          AppColors.video.withValues(alpha: 0.14)
        );
      case DocKind.unknown:
        return (
          Icons.insert_drive_file,
          AppColors.muted,
          AppColors.surfaceSoft
        );
    }
  }
}

/// Document row card with type icon, name, size/date, status, actions.
class DocumentCard extends StatelessWidget {
  final SharedDocument doc;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  /// Send this file straight to the running session. Null hides the button.
  final VoidCallback? onCast;

  /// Why [onCast] is unavailable. Shown as the tooltip on a disabled button,
  /// so a teacher who cannot cast is told what to do about it instead of
  /// finding a greyed-out icon and no explanation.
  final String? castBlockedReason;

  const DocumentCard({
    super.key,
    required this.doc,
    this.selected = false,
    this.onTap,
    this.onOpen,
    this.onRemove,
    this.onCast,
    this.castBlockedReason,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: selected ? AppColors.primarySoft : AppColors.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              FileTypeIcon(
                  kind: doc.kind, extension: doc.extension),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${doc.name}.${doc.extension}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _metaLine(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                    if (doc.status != DocStatus.ready)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _statusPill(doc.status),
                      ),
                  ],
                ),
              ),
              // Sharing also lives on the row tap, which is where the design
              // puts it. This third button is the shortcut for the common case —
              // in a running lesson, tapping cast beats tapping through to the
              // share screen and then the share button — so it is compact,
              // which is what keeps a third affordance from costing the
              // filename 48px on a 320px phone.
              if (onCast != null || castBlockedReason != null)
                IconButton(
                  tooltip: castBlockedReason ?? 'Cast to the active session',
                  icon: const Icon(Icons.cast_connected),
                  color: AppColors.primary,
                  onPressed: onCast,
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                ),
              if (onOpen != null)
                IconButton(
                  tooltip: 'Open',
                  icon: Icon(Icons.open_in_new,
                      color: AppColors.primary),
                  onPressed: onOpen,
                ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove',
                  icon: Icon(Icons.close,
                      color: AppColors.muted),
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _metaLine() {
    final parts = <String>[];
    if (doc.sizeBytes > 0) parts.add(formatBytes(doc.sizeBytes));
    if (doc.lastModified != null) {
      parts.add(formatDateTime(doc.lastModified!));
    }
    if (doc.pageCount > 0) parts.add('${doc.pageCount} pages');
    return parts.isEmpty ? doc.kind.name.toUpperCase() : parts.join(' · ');
  }

  Widget _statusPill(DocStatus status) {
    final (label, color, bg) = switch (status) {
      DocStatus.ready => ('Ready', AppColors.success, AppColors.successBg),
      DocStatus.needsConversion =>
        ('Needs conversion', AppColors.warning, AppColors.warningBg),
      DocStatus.converting =>
        ('Converting…', AppColors.info, AppColors.infoBg),
      DocStatus.conversionFailed =>
        ('Conversion failed', AppColors.error, AppColors.errorBg),
      DocStatus.unsupported =>
        ('Unsupported', AppColors.error, AppColors.errorBg),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
