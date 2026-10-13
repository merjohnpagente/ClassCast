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
          Icon(icon, size: size * 0.42, color: color),
          const SizedBox(height: 1),
          Text(
            extension.isEmpty ? 'FILE' : extension.toUpperCase(),
            style: TextStyle(
              fontSize: size * 0.16,
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
          const Color(0xFFFFEBEB)
        );
      case DocKind.powerpoint:
        return (
          Icons.slideshow,
          AppColors.ppt,
          const Color(0xFFFFF1E3)
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
  final VoidCallback? onShare;
  final VoidCallback? onOpen;
  final VoidCallback? onRemove;

  const DocumentCard({
    super.key,
    required this.doc,
    this.selected = false,
    this.onTap,
    this.onShare,
    this.onOpen,
    this.onRemove,
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
              if (onOpen != null)
                IconButton(
                  tooltip: 'Open',
                  icon: const Icon(Icons.open_in_new,
                      color: AppColors.primary),
                  onPressed: onOpen,
                ),
              if (onShare != null)
                IconButton(
                  tooltip: 'Share to classroom',
                  icon: const Icon(Icons.cast_connected,
                      color: AppColors.primary),
                  onPressed: onShare,
                ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close,
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
