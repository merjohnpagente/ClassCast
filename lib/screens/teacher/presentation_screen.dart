import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../models/classroom_session.dart';
import '../../models/doc_types.dart';
import '../../providers/library_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/document_viewer.dart';
import '../../widgets/office/office_document_scroll_view.dart';
import '../../widgets/state_cards.dart';
import '../../widgets/status_bits.dart';
import 'students_screen.dart';

/// Teacher presentation controller. Mobile: preview top, controls bottom.
/// Desktop: big preview + right-side control panel.
/// Page changes broadcast to students (host WS).
class TeacherPresentationScreen extends StatefulWidget {
  const TeacherPresentationScreen({super.key});

  @override
  State<TeacherPresentationScreen> createState() =>
      _TeacherPresentationScreenState();
}

class _TeacherPresentationScreenState
    extends State<TeacherPresentationScreen> {
  final PdfViewerController _pdf = PdfViewerController();

  /// Page-by-page or continuous scroll. Both keep the class in step: in scroll
  /// mode the page nearest the top is broadcast as the teacher scrolls.
  OfficeViewMode _viewMode = OfficeViewMode.pages;

  @override
  void dispose() {
    _pdf.dispose();
    super.dispose();
  }

  void _goTo(SessionProvider sessions, int page) {
    // Updates locally and POSTs /api/page with the teacher key, which the
    // host broadcasts to every connected student.
    sessions.setPage(page);
  }

  int _lastPdfPage = -1;

  /// Keeps the PDF preview on the page the session is on, so the control bar
  /// actually moves what is on screen (Office documents get the page directly
  /// through [DocumentViewer.page]).
  void _syncPdfPage(int page) {
    if (page == _lastPdfPage) return;
    _lastPdfPage = page;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _pdf.jumpToPage(page);
      } catch (_) {/* the document is still loading */}
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionProvider>();
    final active = sessions.active;

    return Scaffold(
      appBar: AppBar(
        title: Text(active?.name ?? 'Presentation'),
        actions: [
          // Honest about delivery: if the host is not reachable, the teacher
          // is presenting locally only and students are NOT in sync.
          if (!sessions.hostReachable)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: StatusChip(
                label: 'Host offline',
                icon: Icons.cloud_off,
                color: AppColors.error,
                background: AppColors.errorBg,
              ),
            ),
          if (active?.syncPaused ?? false)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: StatusChip(
                  label: 'Paused',
                  icon: Icons.pause_circle_outline,
                  color: AppColors.muted,
                  background: AppColors.surfaceSoft),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: StatusChip(
                  label: 'Live',
                  icon: Icons.sensors,
                  color: AppColors.success,
                  background: AppColors.successBg),
            ),
          IconButton(
            tooltip: 'Students',
            icon: Badge(
              label: Text('${sessions.connectedCount}'),
              child: const Icon(Icons.people_outline),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const StudentsScreen()),
            ),
          ),
        ],
      ),
      body: active == null
          ? const EmptyState(
              icon: Icons.present_to_all,
              title: 'No active session',
              subtitle: 'Create a session and share a document first.',
            )
          : active.documentId == null
              ? EmptyState(
                  icon: Icons.description_outlined,
                  title: 'No document shared',
                  subtitle:
                      'Pick a file from the library to start presenting.',
                  actionLabel: 'Open files',
                  onAction: () => Navigator.of(context).pop(),
                )
              : context.isDesktop
                  ? _desktopLayout(context, sessions, active)
                  : _mobileLayout(context, sessions, active),
    );
  }

  Widget _preview(BuildContext context, ClassroomSession active) {
    final doc = context.read<LibraryProvider>().selected;
    if (doc == null) {
      return const EmptyState(
        icon: Icons.description_outlined,
        title: 'No document shared',
        subtitle: 'Pick a file from the library to start presenting.',
      );
    }
    if (doc.kind != DocKind.pdf) _syncPdfPage(active.page);
    final sessions = context.read<SessionProvider>();
    return DocumentViewer(
      doc: doc,
      controller: _pdf,
      page: active.page,
      // The app only learns how many slides / pages a file really has once it
      // is open; publish that so students get the same total.
      onPageCount: (count) => _publishPageCount(context, count),
      viewMode: _viewMode,
      onPageChanged: (page) {
        // Scrolling is teacher-driven; broadcasting the page keeps every
        // student on the same screen as the teacher.
        if (sessions.active?.page != page) sessions.setPage(page);
      },
    );
  }

  /// Scrolling only means something for Office documents; a PDF already
  /// scrolls inside its own viewer.
  bool get _supportsScrollMode {
    final doc = context.read<LibraryProvider>().selected;
    if (doc == null) return false;
    return doc.kind == DocKind.powerpoint ||
        doc.kind == DocKind.word ||
        doc.kind == DocKind.excel;
  }

  void _publishPageCount(BuildContext context, int count) {
    final sessions = context.read<SessionProvider>();
    final active = sessions.active;
    if (active == null) return;
    if (active.totalPages == count) return;
    if (active.documentId == null) return;
    sessions.setTotalPages(count);
  }

  Widget _mobileLayout(BuildContext context, SessionProvider sessions,
      ClassroomSession active) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              context.pagePadding, 8, context.pagePadding, 0),
          child: _docHeader(context, active),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(context.pagePadding),
            child: _preview(context, active),
          ),
        ),
        _controlBar(context, sessions, active),
      ],
    );
  }

  Widget _desktopLayout(BuildContext context, SessionProvider sessions,
      ClassroomSession active) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: EdgeInsets.all(context.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _docHeader(context, active),
                const SizedBox(height: 8),
                Expanded(child: _preview(context, active)),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 300,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionHeader(title: 'Controls'),
              _controlPanel(context, sessions, active),
              const SectionHeader(title: 'Session'),
              _sessionInfo(context, sessions, active),
            ],
          ),
        ),
      ],
    );
  }

  Widget _docHeader(BuildContext context, ClassroomSession active) {
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
        StatusChip.connected(),
      ],
    );
  }

  Widget _controlBar(BuildContext context, SessionProvider sessions,
      ClassroomSession active) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          context.pagePadding, 8, context.pagePadding, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _navBtn(Icons.skip_previous, 'Previous',
                  active.page <= 1
                      ? null
                      : () => _goTo(sessions, active.page - 1)),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${active.page}'
                  '${active.totalPages > 0 ? ' / ${active.totalPages}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_supportsScrollMode)
                      IconButton(
                        tooltip: _viewMode == OfficeViewMode.pages
                            ? 'Switch to scrolling'
                            : 'Switch to one page at a time',
                        icon: Icon(
                          _viewMode == OfficeViewMode.pages
                              ? Icons.swipe_vertical
                              : Icons.crop_free,
                          size: 20,
                        ),
                        onPressed: () => setState(() {
                          _viewMode = _viewMode == OfficeViewMode.pages
                              ? OfficeViewMode.scroll
                              : OfficeViewMode.pages;
                        }),
                      ),
                    IconButton(
                      tooltip: active.syncPaused
                          ? 'Resume sync'
                          : 'Pause sync',
                      icon: Icon(active.syncPaused
                          ? Icons.play_arrow
                          : Icons.pause),
                      onPressed: () => sessions.setPaused(!active.syncPaused),
                    ),
                    FilledButton.icon(
                      onPressed: () => sessions.endSession(),
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('End'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.error,
                        minimumSize: const Size(48, 44),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _navBtn(Icons.skip_next, 'Next',
                    active.totalPages > 0 &&
                            active.page >= active.totalPages
                        ? null
                        : () => _goTo(sessions, active.page + 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlPanel(BuildContext context, SessionProvider sessions,
      ClassroomSession active) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: active.page <= 1
                        ? null
                        : () => _goTo(sessions, active.page - 1),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.inkSecondary,
                      disabledForegroundColor: AppColors.muted,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                    ),
                    icon: const Icon(Icons.skip_previous, size: 18),
                    label: const Text('Prev'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    onPressed: active.totalPages > 0 &&
                            active.page >= active.totalPages
                        ? null
                        : () => _goTo(sessions, active.page + 1),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.inkSecondary,
                      disabledForegroundColor: AppColors.muted,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                    ),
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text('Next'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pause sync'),
              subtitle: const Text('Freeze student screens'),
              value: active.syncPaused,
              onChanged: (v) => sessions.setPaused(v),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => sessions.endSession(),
              icon: const Icon(Icons.stop),
              label: const Text('End Presentation'),
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionInfo(BuildContext context, SessionProvider sessions,
      ClassroomSession active) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session ID: ${active.id}'),
            Text('${sessions.connectedCount} students connected'),
            if (active.joinAddress.isNotEmpty)
              Text(active.joinAddress,
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// Page arrows stay out of the way: the deck is the content, and two big
  /// filled circles next to it looked louder than the slide itself.
  Widget _navBtn(IconData icon, String tip, VoidCallback? onTap) {
    return IconButton(
      tooltip: tip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: AppColors.inkSecondary.withAlpha(170),
        disabledForegroundColor: AppColors.muted.withAlpha(70),
        minimumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon),
      onPressed: onTap,
    );
  }
}
