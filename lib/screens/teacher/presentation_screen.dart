import 'dart:async';

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
import '../../widgets/motion.dart';
import '../../widgets/office/office_document_scroll_view.dart';
import '../../widgets/state_cards.dart';
import '../../widgets/status_bits.dart';
import '../../widgets/ui_kit.dart';
import 'student_preview_screen.dart';
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
  void initState() {
    super.initState();
    // Teachers usually switch the hotspot on *after* starting the session, so
    // the address in the QR is stale by the time they open the presentation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<SessionProvider>().refreshNetwork());
    });
  }

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
        title: Text(active?.name ?? 'Classroom Session'),
        actions: [
          // Honest about delivery: if the host is not reachable, the teacher
          // is presenting locally only and students are NOT in sync.
          if (!sessions.hostReachable || !sessions.classroomReady)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: StatusChip(
                label: sessions.classroomError == null
                    ? 'Host offline'
                    : 'Not sharing',
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
            tooltip: sessions.raisedHands.isEmpty
                ? 'Students'
                : '${sessions.raisedHands.length} hand(s) raised',
            // One badge, both numbers: students connected, and how many have a
            // hand up right now.
            icon: Badge(
              isLabelVisible: true,
              label: Text(sessions.raisedHands.isEmpty
                  ? '${sessions.connectedCount}'
                  : '${sessions.connectedCount} · '
                      '${sessions.raisedHands.length} raised'),
              child: Icon(
                sessions.raisedHands.isEmpty
                    ? Icons.people_outline
                    : Icons.pan_tool,
                color: sessions.raisedHands.isEmpty
                    ? null
                    : AppColors.warning,
              ),
            ),
            onPressed: () => _showStudents(context, sessions),
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
    // Only the PDF viewer has its own controller to steer, so only a PDF gets
    // its page pushed here. This read `!=` for years, which meant the arrows
    // moved every Office document and never moved the one format where the
    // teacher could actually see the page they were on.
    if (doc.kind == DocKind.pdf) _syncPdfPage(active.page);
    final sessions = context.read<SessionProvider>();
    final viewer = DocumentViewer(
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
    // A PDF draws itself; an Office page is painted by us, so the turn has to
    // be animated or it reads as a dropped frame.
    if (doc.kind == DocKind.pdf) return viewer;
    return PageSwitcher(
      identity: _viewMode == OfficeViewMode.scroll
          ? 'scroll'
          : 'page-${active.page}',
      child: viewer,
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
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                context.pagePadding,
                context.pagePadding,
                context.pagePadding,
                8),
            child: _preview(context, active),
          ),
        ),
        _pageRow(context, sessions, active),
        _sessionBar(context, sessions, active),
      ],
    );
  }

  /// The page control as the design draws it: a quiet arrow, the counter, and
  /// the play button in the middle — on a single row that cannot overflow.
  ///
  /// This used to be two arrows flanking a column of five controls. The
  /// column was not a flex child, so it was measured at its natural width and
  /// the row overflowed by over a hundred pixels on every phone narrower than
  /// ~436px. The extra controls moved to their own bar below.
  Widget _pageRow(BuildContext context, SessionProvider sessions,
      ClassroomSession active) {
    final theme = Theme.of(context);
    final atStart = active.page <= 1;
    final atEnd = active.totalPages > 0 && active.page >= active.totalPages;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
      child: Row(
        children: [
          _ArrowButton(
            icon: Icons.skip_previous,
            tooltip: 'Previous page',
            onPressed: atStart ? null : () => _goTo(sessions, active.page - 1),
          ),
          Expanded(
            child: Text(
              active.totalPages > 0
                  ? 'Page ${active.page} of ${active.totalPages}'
                  : 'Page ${active.page}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          _ArrowButton(
            icon: Icons.skip_next,
            tooltip: 'Next page',
            onPressed: atEnd ? null : () => _goTo(sessions, active.page + 1),
          ),
        ],
      ),
    );
  }

  /// The session controls the teacher reaches for mid-lesson: sync pause,
  /// pull-everyone-back, student preview, and the room size.
  Widget _sessionBar(BuildContext context, SessionProvider sessions,
      ClassroomSession active) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          context.pagePadding, 10, context.pagePadding, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () =>
                        sessions.setPaused(!active.syncPaused),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.inkSecondary,
                    ),
                    icon: Icon(
                      active.syncPaused
                          ? Icons.play_arrow
                          : Icons.pause,
                      size: 20,
                    ),
                    label: Text(active.syncPaused ? 'Resume' : 'Pause'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => sessions.takeControl(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.inkSecondary,
                    ),
                    icon: const Icon(Icons.my_location, size: 20),
                    label: const Text('Sync all'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            StudentPreviewScreen(session: active),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.inkSecondary,
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                    label: const Text('Preview'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            AppListRow(
              icon: Icons.people,
              title: sessions.connectedCount == 0
                  ? 'No students yet'
                  : '${sessions.connectedCount} connected',
              subtitle: sessions.raisedHands.isEmpty
                  ? 'Share the QR code so they can join'
                  : '${sessions.raisedHands.length} hand(s) raised',
              trailing: const AppChevron(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StudentsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A circular arrow button. Sized at 48 so it is a real tap target on a
  /// phone, which the previous 36px shrink-wrapped button was not.
  Widget _ArrowButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      label: tooltip,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 24,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor:
              enabled ? AppColors.primarySoft : AppColors.surfaceSoft,
          foregroundColor:
              enabled ? AppColors.primary : AppColors.muted,
          minimumSize: const Size(48, 48),
          shape: const CircleBorder(),
        ),
      ),
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

  /// Ending a session drops every student. One tap should not be enough —
  /// especially from a control the teacher reaches for mid-lesson.
  void _confirmEnd(BuildContext context, SessionProvider sessions) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End session?'),
        content: const Text(
          'Students will be disconnected and the join code stops working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.of(ctx).pop();
              sessions.endSession();
            },
            child: const Text('End session'),
          ),
        ],
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
              onPressed: () => _confirmEnd(context, sessions),
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
            if (active.joinAddress.isNotEmpty)
              Text(active.joinAddress,
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 10),
            // Who is actually watching, live — a teacher needs this to know
            // whether a student is missing before the lesson moves on.
            _studentList(context, sessions),
          ],
        ),
      ),
    );
  }

  /// Live roster: names appear as students join, disappear as they leave.
  Widget _studentList(BuildContext context, SessionProvider sessions) {
    final students = sessions.participants;
    if (students.isEmpty) {
      return Row(
        children: [
          const Icon(Icons.groups_outlined, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Waiting for students…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.groups, size: 18, color: AppColors.success),
            const SizedBox(width: 8),
            Text('${students.length} connected',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (sessions.raisedHands.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.pan_tool, size: 14, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Text('${sessions.raisedHands.length} hand(s)',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.warning)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (final student in students)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  sessions.raisedHands.containsKey(student.id)
                      ? Icons.pan_tool
                      : Icons.circle,
                  size: sessions.raisedHands.containsKey(student.id) ? 14 : 8,
                  color: sessions.raisedHands.containsKey(student.id)
                      ? AppColors.warning
                      : AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    student.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                // Where this student is, when the teacher let them browse.
                if (sessions.studentPages[student.id] != null)
                  Text('p${sessions.studentPages[student.id]}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted)),
                if (sessions.raisedHands.containsKey(student.id))
                  IconButton(
                    tooltip: 'Lower hand',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    icon: const Icon(Icons.check, color: AppColors.success),
                    onPressed: () => sessions.lowerHand(student.id),
                  ),
                // Pull a wandering student back onto the class page.
                IconButton(
                  tooltip: 'Take control',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(Icons.my_location,
                      color: AppColors.primary),
                  onPressed: () => sessions.takeControl(
                      participantId: student.id),
                ),
                if (student.deviceType.isNotEmpty)
                  Text(student.deviceType,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ),
      ],
    );
  }

  /// Mobile equivalent of the roster panel: the same list, in a sheet, so the
  /// teacher can check the room without leaving the presentation.
  void _showStudents(BuildContext context, SessionProvider sessions) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Students',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 12),
              // Built inside the sheet so it keeps watching the provider.
              _studentList(sheetContext, sessions),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const StudentsScreen()));
                  },
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Manage students'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
