import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../models/classroom_session.dart';
import '../../models/doc_types.dart';
import '../../models/shared_document.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/document_viewer.dart';
import '../../widgets/video_sync.dart';
import '../../widgets/motion.dart';
import '../../widgets/state_cards.dart';

/// Exactly what a student sees, on the teacher's own screen.
///
/// This is not a mock-up: it builds the same [DocumentViewer] from the same
/// session snapshot a student's device would receive, so if a slide looks
/// wrong here it looks wrong there. That is the whole point — the teacher can
/// check the room's view without walking to a student's desk.
class StudentPreviewScreen extends StatefulWidget {
  final ClassroomSession session;

  const StudentPreviewScreen({super.key, required this.session});

  @override
  State<StudentPreviewScreen> createState() => _StudentPreviewScreenState();
}

class _StudentPreviewScreenState extends State<StudentPreviewScreen> {
  final PdfViewerController _pdf = PdfViewerController();

  @override
  void dispose() {
    _pdf.dispose();
    super.dispose();
  }

  /// The same document the student's viewer would build from this snapshot.
  SharedDocument? _documentFor() {
    final session = widget.session;
    final name = session.documentName;
    if (name == null || name.isEmpty) return null;
    final dot = name.lastIndexOf('.');
    final base = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
    return SharedDocument(
      id: session.documentId ?? '',
      name: base,
      extension: ext,
      kind: SupportedFiles.kindOf(ext),
      status: SupportedFiles.statusFor(ext),
      pageCount: session.totalPages,
      currentPage: session.page,
      remoteUrl: session.documentUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final doc = _documentFor();

    if (doc == null) {
      return const EmptyState(
        icon: Icons.hourglass_bottom,
        title: 'Nothing shared yet',
        subtitle: 'Share a document and every student will see it here too.',
      );
    }

    // Jump the local viewer onto the class page, exactly as a student does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _pdf.jumpToPage(session.page);
      } catch (_) {/* the document is not ready to page yet */}
    });

final viewer = DocumentViewer(
      doc: doc,
      controller: _pdf,
      remoteUrl: doc.remoteUrl,
      page: session.page,
      // A video is followed here exactly as a student follows it — this screen
      // exists to be what they see, and with no playback state it showed a
      // panel saying the file was gone.
      video: doc.kind == DocKind.video
          ? VideoSync(
              positionMs: session.videoPositionMs,
              playing: session.videoPlaying,
              durationMs: session.videoDurationMs,
              frozen: session.syncPaused,
            )
          : null,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(session.name)),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(context.pagePadding),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: doc.kind == DocKind.pdf || doc.kind == DocKind.video
                      ? viewer
                      : PageSwitcher(
                          identity: 'preview-${session.page}',
                          child: viewer,
                        ),
                ),
              ),
            ),
          ),
                ),
              ),
            ),
          ),
          _statusLine(context, session),
          const SizedBox(height: 8),
          _pageBar(session),
        ],
      ),
    );
  }

  /// One line saying what this screen is and what the students may do.
  ///
  /// It used to be a row of bare chevrons and a hand icon with no tap handlers
  /// at all. Chevrons are the universal page-control glyph — and the app uses
  /// the very same ones as real buttons in the student viewer — so a
  /// screen-reader user was told about three apparently-tappable icons that
  /// did nothing, and everyone else saw controls that were not controls.
  Widget _statusLine(BuildContext context, ClassroomSession session) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined,
              size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This is what your students see. '
              '${session.allowStudentNav ? 'They may also turn pages.' : 'The teacher controls every screen.'}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  /// The page bar, drawn exactly as the student's own viewer draws it so the
  /// teacher recognises the screen they are about to show the room.
  ///
  /// The arrows are deliberately inert: this screen mirrors the class, and the
  /// teacher drives the page from the presentation screen, not from here.
  Widget _pageBar(ClassroomSession session) {
    // A video has no pages, and the player's own bar already says where the
    // class is. A row of inert arrows under a recording says nothing at all.
    if (session.videoDurationMs > 0 ||
        SupportedFiles.kindOf(
                _extensionOf(session.documentName)) ==
            DocKind.video) {
      return const SizedBox.shrink();
    }
    final total = session.totalPages;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const _CircleArrow(
                icon: Icons.chevron_left, tooltip: 'Previous page'),
            Expanded(
              child: Text(
                total > 0 ? '${session.page} / $total' : '${session.page}',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const _CircleArrow(
                icon: Icons.chevron_right, tooltip: 'Next page'),
          ],
        ),
      ),
    );
  }
}

/// The extension of a shared file's name, lowercased and without the dot.
  static String _extensionOf(String? name) {
    if (name == null || name.isEmpty) return '';
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

/// A circular arrow shown in its disabled state, because the teacher does not
/// turn pages from the preview. Same 48dp footprint as the student's, so the
/// two screens line up.
class _CircleArrow extends StatelessWidget {
  final IconData icon;
  final String tooltip;

  const _CircleArrow({required this.icon, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: null,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: AppColors.surfaceSoft,
        disabledForegroundColor: AppColors.muted,
        minimumSize: const Size(48, 48),
        shape: const CircleBorder(),
      ),
    );
  }
}
