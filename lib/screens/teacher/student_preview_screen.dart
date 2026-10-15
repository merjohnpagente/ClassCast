import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../models/classroom_session.dart';
import '../../models/doc_types.dart';
import '../../models/shared_document.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/document_viewer.dart';
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
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student view'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${doc.name}.${doc.extension}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.muted),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ContentWidth(
          maxWidth: 1000,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FadeIn(
                child: _header(session),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: doc.kind == DocKind.pdf
                    ? viewer
                    : PageSwitcher(
                        identity: 'preview-${session.page}',
                        child: viewer,
                      ),
              ),
              const SizedBox(height: 8),
              _footer(session),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ClassroomSession session) {
    final total = session.totalPages;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              session.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          Text(
            total > 0 ? 'Page ${session.page} / $total' : 'Page ${session.page}',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _footer(ClassroomSession session) {
    return Row(
      children: [
        const Icon(Icons.chevron_left,
            size: 20, color: AppColors.muted),
        Expanded(
          child: Text(
            'Teacher controls the presentation'
            '${session.allowStudentNav ? ' · you may also turn pages' : ''}',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.muted),
          ),
        ),
        const Icon(Icons.chevron_right,
            size: 20, color: AppColors.muted),
        const Icon(Icons.pan_tool_outlined,
            size: 20, color: AppColors.muted),
        const SizedBox(width: 16),
      ],
    );
  }
}
