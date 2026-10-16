import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../models/classroom_session.dart';
import '../../models/doc_types.dart';
import '../../models/shared_document.dart';
import '../../providers/sync_provider.dart';
import '../../services/classcast_client.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/document_viewer.dart';
import '../../widgets/motion.dart';
import '../../widgets/state_cards.dart';
import '../../widgets/status_bits.dart';

/// Distraction-free student viewer. Follows the teacher page automatically.
/// Students never control the teacher presentation.
class StudentViewerScreen extends StatefulWidget {
  const StudentViewerScreen({super.key});

  @override
  State<StudentViewerScreen> createState() => _StudentViewerScreenState();
}

class _StudentViewerScreenState extends State<StudentViewerScreen> {
  final PdfViewerController _pdf = PdfViewerController();
  bool _fullscreen = false;
  int _lastSeenPage = -1;

  @override
  void dispose() {
    _pdf.dispose();
    super.dispose();
  }

  /// Rebuild the shared document from the session snapshot so the viewer
  /// renders the teacher's real file instead of a placeholder asset.
  SharedDocument? _documentFor(ClassroomSession? session) {
    final name = session?.documentName;
    if (session == null || name == null || name.isEmpty) return null;
    final dot = name.lastIndexOf('.');
    final base = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
    final kind = SupportedFiles.kindOf(ext);
    return SharedDocument(
      id: session.documentId ?? '',
      name: base,
      extension: ext,
      kind: kind,
      // Status by extension: a legacy .ppt the teacher shared by mistake must
      // not look like a file the student app can open.
      status: SupportedFiles.statusFor(ext),
      pageCount: session.totalPages,
      currentPage: session.page,
      remoteUrl: session.documentUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final active = sync.snapshot;

    if (active == null || active.documentId == null) {
      return const EmptyState(
        icon: Icons.hourglass_bottom,
        title: 'Waiting for the teacher',
        subtitle: 'The shared document will appear here.',
      );
    }
    if (sync.link == LinkState.ended || !active.isActive) {
      return ErrorState(
        icon: Icons.meeting_room_outlined,
        title: 'Session ended',
        message: 'The teacher ended this classroom session.',
        retryLabel: 'Leave',
        onRetry: () => sync.leave(),
      );
    }

    // Mirror the teacher page into the local PDF controller.
    if (active.page != _lastSeenPage) {
      _lastSeenPage = active.page;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _pdf.jumpToPage(active.page);
        } catch (_) {/* page not ready yet */}
      });
    }

    if (_fullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: _preview(active)),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: 'Exit full screen',
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.black54),
                  icon: const Icon(Icons.fullscreen_exit,
                      color: Colors.white),
                  onPressed: () =>
                      setState(() => _fullscreen = false),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // One centred column, so the title, the page and the controls line up
    // with each other instead of each spanning the whole screen.
    return Center(
      child: ContentWidth(
        maxWidth: 1000,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, active, sync),
            const SizedBox(height: 8),
            Expanded(child: _preview(active)),
            const SizedBox(height: 8),
            _footer(context, active),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ClassroomSession active,
      SyncProvider sync) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(active.documentName ?? 'Document',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  )),
              Text(
                active.totalPages > 0
                    ? 'Page ${active.page} / ${active.totalPages}'
                    : 'Page ${active.page}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        if (sync.link == LinkState.reconnecting)
          const StatusChip.reconnecting()
        else if (sync.link == LinkState.live)
          const StatusChip.live()
        else
          const StatusChip.offline(),
        if (sync.syncPaused) ...[
          const SizedBox(width: 6),
          const StatusChip.paused(),
        ],
      ],
    );
  }

  Widget _preview(ClassroomSession active) {
    final doc = _documentFor(active);
    if (doc == null) {
      return const EmptyState(
        icon: Icons.hourglass_bottom,
        title: 'Preparing the document',
        subtitle:
            'The teacher is sending the file for this slide deck.',
      );
    }
    // Students stream the file from the teacher host over the local
    // network; no bundled sample asset is used.
    final viewer = DocumentViewer(
      doc: doc,
      controller: _pdf,
      remoteUrl: doc.remoteUrl,
      page: active.page,
    );
    if (doc.kind == DocKind.pdf) return viewer;
    return PageSwitcher(identity: 'page-${active.page}', child: viewer);
  }

  /// Reports a self-driven page turn to the teacher.
  ///
  /// Only when the teacher allowed student navigation; the teacher sees where
  /// this student is, but the class page stays the teacher's.
  void _reportLocalPage(int page) {
    if (page == _lastReportedPage) return;
    _lastReportedPage = page;
    final sync = context.read<SyncProvider>();
    if (sync.canNavigate) sync.reportPage(page);
  }

  int _lastReportedPage = -1;

  Widget _footer(BuildContext context, ClassroomSession active) {
    final sync = context.watch<SyncProvider>();
    final canNav = sync.canNavigate;
    final canDownload = active.allowDownload;

    // The page bar is the design's: arrow, counter, arrow.
    final pageBar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _ArrowButton(
              icon: Icons.chevron_left,
              tooltip: 'Previous page',
              onPressed: !canNav || active.page <= 1
                  ? null
: () {
                  final next = active.page - 1;
                  // The controller is only attached for a PDF. An Office
                  // page or an image has no `SfPdfViewer` behind it, so an
                  // unguarded nextPage()/previousPage() threw on exactly the
                  // documents that support student navigation. The Office
                  // canvas follows the page through `_reportLocalPage`.
                  try {
                    _pdf.previousPage();
                  } catch (_) {/* not a PDF */}
                  _reportLocalPage(next);
                },
            ),
            Expanded(
              child: Text(
                active.totalPages > 0
                    ? '${active.page} / ${active.totalPages}'
                    : '${active.page}',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            _ArrowButton(
              icon: Icons.chevron_right,
              tooltip: 'Next page',
              onPressed: !canNav ||
                      (active.totalPages > 0 &&
                          active.page >= active.totalPages)
                  ? null
: () {
                  final next = active.page + 1;
                  try {
                    _pdf.nextPage();
                  } catch (_) {/* not a PDF */}
                  _reportLocalPage(next);
                },
            ),
          ],
        ),
      ),
    );

    // Everything else goes on its own row with a label. It used to be five
    // bare icons sharing one row with the explanatory text, which left the
    // text 48px — and zero, with downloads enabled — on a 320px phone, so the
    // one sentence telling a student what they are allowed to do was
    // unreadable exactly when it mattered.
    final actions = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              sync.takenOver
                  ? 'The teacher took control — back on the class page'
                  : 'Teacher controls the presentation'
                      '${canNav ? ' · you may also turn pages' : ''}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.muted),
            ),
          ),
          IconButton(
            tooltip: sync.handRaised ? 'Lower hand' : 'Raise hand',
            icon: Icon(
              sync.handRaised ? Icons.pan_tool : Icons.pan_tool_outlined,
              color: sync.handRaised ? AppColors.warning : null,
            ),
            onPressed: () => sync.setHandRaised(!sync.handRaised),
          ),
          IconButton(
            tooltip: 'Full screen',
            icon: const Icon(Icons.fullscreen),
            onPressed: () => setState(() => _fullscreen = true),
          ),
          if (canDownload)
            IconButton(
              tooltip: 'Download (allowed by teacher)',
              icon: const Icon(Icons.download_outlined),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Download starts when the host serves the file.')),
                );
              },
            ),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        actions,
        const SizedBox(height: 4),
        pageBar,
      ],
    );
  }
}

/// A circular arrow button sized to be a real tap target on a phone.
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: tooltip,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: enabled ? AppColors.primarySoft : AppColors.surfaceSoft,
          foregroundColor: enabled ? AppColors.primary : AppColors.muted,
          minimumSize: const Size(48, 48),
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}
