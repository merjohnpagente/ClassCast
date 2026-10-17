import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../models/classroom_session.dart';
import '../../models/doc_types.dart';
import '../../models/shared_document.dart';
import '../../providers/app_state.dart';
import '../../providers/sync_provider.dart';
import '../../services/classcast_client.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/chrome_toggle.dart';
import '../../widgets/document_preview.dart';
import '../../widgets/document_viewer.dart';
import '../../widgets/motion.dart';
import '../../widgets/office/office_document_scroll_view.dart';
import '../../widgets/state_cards.dart';
import '../../widgets/status_bits.dart';
import '../../widgets/video_sync.dart';

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
  int _lastClassPage = -1;
  int _localPage = 1;
  bool _downloading = false;

  @override
  void dispose() {
    _pdf.dispose();
    super.dispose();
  }

  /// The page this student is actually looking at.
  ///
  /// While the teacher allows independent navigation and has not taken the
  /// screen back, the student's own page wins. Otherwise — and whenever the
  /// class page moves, because then following it is the whole point — it is
  /// the teacher's page. Without this, the arrows below reported a page the
  /// screen never drew: the viewer kept rendering `active.page`, so a student
  /// allowed to look ahead turned a virtual page and saw nothing happen.
  int _viewPageFor(ClassroomSession active, bool canNav) {
    if (!canNav) {
      _lastClassPage = active.page;
      _localPage = active.page;
      return active.page;
    }
    if (active.page != _lastClassPage) {
      _lastClassPage = active.page;
      _localPage = active.page;
    }
    return _localPage;
  }

  /// Turn to a page on this student's own copy, and tell the teacher where
  /// they landed. The class page does not move.
  void _turnTo(int page) {
    if (page < 1) return;
    setState(() => _localPage = page);
    _reportLocalPage(page);
  }

  Future<void> _download(BuildContext context, SyncProvider sync) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _downloading = true);
    messenger.showSnackBar(
      const SnackBar(content: Text('Downloading from the teacher…')),
    );
    final result = await sync.downloadDocument();
    if (!mounted) return;
    setState(() => _downloading = false);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
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

    final viewPage = _viewPageFor(active, sync.canNavigate);

    // Mirror the page being drawn into the local PDF controller. For a PDF
    // this is what a local page turn actually looks like; for everything else
    // the controller has no document and the jump is a no-op.
    if (viewPage != _lastSeenPage) {
      _lastSeenPage = viewPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _pdf.jumpToPage(viewPage);
        } catch (_) {/* page not ready yet */}
      });
    }

    if (_fullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                  child: _previewPanel(context, viewPage, _videoSync(sync))),
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
    // with each other instead of each spanning the whole screen. The app
    // bar's toggle is the only way in or out of the hidden chrome; a tap on
    // the page itself no longer touches it, so a page turn or a stray tap
    // can never drop the title and the controls.
    final chrome = ChromeToggleScope.maybeOf(context);
    final hideChrome = chrome?.hidden ?? false;

    return Stack(
      children: [
        Positioned.fill(
          child: Center(
            child: ContentWidth(
              maxWidth: 1000,
              // A page, not a column of text: on a laptop it should use the
              // screen rather than sit in a 1000px strip of a 1920 one.
              wide: true,
              // With the shell's app bar away nothing insets the body, so
              // the slide would run under the status and gesture bars.
              child: hideChrome
                  ? SafeArea(
                      child: _pageColumn(context, active, sync, viewPage))
                  : _pageColumn(context, active, sync, viewPage),
            ),
          ),
        ),
        if (hideChrome)
          // Top corner, and never over the content. The button used to sit in
          // the bottom-left, chosen because the zoom bar owns the
          // bottom-right — but then came video, whose own bar runs the full
          // width of the bottom edge, and the eye landed on top of play/pause
          // so neither could be used. The widget owns the placement now; this
          // stack only decides that it exists at all.
          const Positioned.fill(child: ChromeToggleHint()),
      ],
    );
  }

  /// Title, page, controls. Hidden chrome drops the first and the last.
  Widget _pageColumn(BuildContext context, ClassroomSession active,
      SyncProvider sync, int viewPage) {
    final chrome = ChromeToggleScope.maybeOf(context);
    final hideChrome = chrome?.hidden ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!hideChrome) ...[
          _header(context, active, sync, viewPage),
          const SizedBox(height: 8),
        ],
        Expanded(child: _previewPanel(context, viewPage, _videoSync(sync))),
        if (!hideChrome) ...[
          const SizedBox(height: 8),
          _footer(context, active, viewPage),
        ],
      ],
    );
  }

  /// The document, rebuilt on nothing but a new file, a new page or a new
  /// total. This screen rebuilds on every socket frame — the teacher's page, the
  /// hand badge, the paused chip, a reconnect — and the document came along for
  /// all of it. The page passed as `mode` is the one being *drawn*: without it
  /// a student's own page turn changed nothing, because the cache still
  /// answered with the subtree built for the old page.
  ///
  /// The reading mode rides in the same value for the same reason: toggling
  /// page-by-page to scroll is a different subtree, and a gate that compared
  /// only the page would hand back the old one and leave the switch dead.
  Widget _previewPanel(BuildContext context, int viewPage, VideoSync? video) {
    final scrollView = context.watch<AppState>().scrollView;
    return SyncDocumentPreview(
      mode: (viewPage, scrollView),
      builder: (context, snapshot) => _preview(snapshot, viewPage, video),
    );
  }

  /// Playback state for a shared video, from the teacher.
  ///
  /// Sound is on and the mute button is right there: a recorded lesson the
  /// student cannot hear is not a lesson. The mute itself is this device's own
  /// business, so it lives in [AppState] and is never sent to anyone.
  VideoSync? _videoSync(SyncProvider sync) {
    final muted = context.watch<AppState>().videoMuted;
    return VideoSync(
      isTeacher: false,
      positionMs: sync.videoPositionMs,
      playing: sync.videoPlaying,
      durationMs: sync.videoDurationMs,
      // The teacher's freeze stops a video as surely as it stops a page.
      frozen: sync.syncPaused,
      muted: muted,
      onMutedChanged: (value) =>
          context.read<AppState>().setVideoMuted(value),
    );
  }

  Widget _header(BuildContext context, ClassroomSession active,
      SyncProvider sync, int viewPage) {
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
                _subtitleFor(active, viewPage),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        if (sync.link == LinkState.reconnecting)
          StatusChip.reconnecting()
        else if (sync.link == LinkState.live)
          StatusChip.live()
        else
          StatusChip.offline(),
        if (sync.syncPaused) ...[
          const SizedBox(width: 6),
          StatusChip.paused(),
        ],
      ],
    );
  }

  /// The line under the file's name.
  ///
  /// A video has no pages: it has a position, and the player's own bar shows
  /// that. Saying "Page 1 / 1" over a recording would be a lie about what the
  /// controls do.
  String _subtitleFor(ClassroomSession active, int viewPage) {
    if (_documentFor(active)?.kind == DocKind.video) {
      final duration = active.videoDurationMs;
      final minutes = Duration(milliseconds: duration).inMinutes;
      final seconds = Duration(milliseconds: duration).inSeconds % 60;
      if (duration <= 0) return 'Video';
      return 'Video · $minutes:${seconds.toString().padLeft(2, '0')}';
    }
    return active.totalPages > 0
        ? 'Page $viewPage / ${active.totalPages}'
        : 'Page $viewPage';
  }

  Widget _preview(ClassroomSession active, int viewPage, VideoSync? video) {
    final doc = _documentFor(active);
    if (doc == null) {
      return const EmptyState(
        icon: Icons.hourglass_bottom,
        title: 'Preparing the document',
        subtitle:
            'The teacher is sending the file for this slide deck.',
      );
    }
    // How this device reads an Office document: the teacher's page, or one
    // long scroll. A PDF, an image and a video ignore this — they scroll or
    // play on their own terms, and the switch is not offered for them.
    final scrollView = context.watch<AppState>().scrollView;
    // Students stream the file from the teacher host over the local
    // network; no bundled sample asset is used.
    final viewer = DocumentViewer(
      doc: doc,
      controller: _pdf,
      remoteUrl: doc.remoteUrl,
      page: viewPage,
      video: video,
      viewMode: scrollView ? OfficeViewMode.scroll : OfficeViewMode.pages,
      // Scrolling reports the page nearest the top, exactly as the teacher's
      // own scroll does; the student's local page follows it so the counter
      // and the arrows stay honest, and the teacher is told where they
      // landed — a no-op unless students are allowed to navigate.
      onPageChanged: _turnTo,
    );
    // A video is never wrapped: the page identity changes whenever the teacher
    // moves, and rebuilding the player each time would restart the recording
    // from the top.
    if (doc.kind != DocKind.video) {
      // Scroll mode keeps one identity: a scroll is a continuous movement, and
      // re-keying it on every page boundary would restart the gesture under
      // the student's finger.
      return PageSwitcher(
        identity: scrollView ? 'scroll' : 'page-$viewPage',
        child: viewer,
      );
    }
    return viewer;
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

  Widget _footer(BuildContext context, ClassroomSession active, int viewPage) {
    final sync = context.watch<SyncProvider>();
    final canNav = sync.canNavigate;
    final canDownload = active.allowDownload;

    // The page bar is the design's: arrow, counter, arrow.
    //
    // The arrows turn the page being drawn — PDF or Office alike — through
    // `_turnTo`, which moves the local page, reports it to the teacher, and
    // lets the mirror in `build` do the PDF jump. Calling the PDF controller
    // directly (when it was attached at all) never moved an Office document.
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
              onPressed:
                  !canNav || viewPage <= 1 ? null : () => _turnTo(viewPage - 1),
            ),
            Expanded(
              child: Text(
                active.totalPages > 0
                    ? '$viewPage / ${active.totalPages}'
                    : '$viewPage',
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
                      (active.totalPages > 0 && viewPage >= active.totalPages)
                  ? null
                  : () => _turnTo(viewPage + 1),
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
              icon: _downloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              onPressed:
                  _downloading ? null : () => _download(context, sync),
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
