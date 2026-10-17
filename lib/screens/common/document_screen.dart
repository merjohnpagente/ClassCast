import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../models/doc_types.dart';
import '../../models/shared_document.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/document_viewer.dart';
import '../../widgets/video_sync.dart';

/// A document on its own, with nothing being shared and nobody watching.
///
/// This exists because the file list had a button labelled "Open" that did
/// not open anything — it only marked the file as selected, which is not what
/// a teacher pressing "Open" is asking for. Checking a slide deck before you
/// show it to thirty people is a reasonable thing to want.
class DocumentScreen extends StatefulWidget {
  final SharedDocument doc;

  const DocumentScreen({super.key, required this.doc});

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  /// The PDF viewer needs a controller and owns nothing, so this screen keeps
  /// it — the same pattern the presentation screen uses.
  final PdfViewerController _pdf = PdfViewerController();

  int _page = 1;

  @override
  void dispose() {
    _pdf.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.doc.name;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '${name}.${widget.doc.extension}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    // Nothing is being shared from this screen, so say so
                    // rather than letting it look like a live classroom.
                    'Preview only — nothing is shared to the class',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, context.pagePadding),
              child: DocumentViewer(
                doc: widget.doc,
                controller: _pdf,
                page: _page,
                onPageChanged: (p) {
                  if (p != _page) setState(() => _page = p);
                },
                // A recording checked before it is shown to thirty people plays
                // like a recording, from this device's own copy. Without a
                // playback state the viewer said the file was gone — which is
                // a thing it says when a file has actually gone.
                video: widget.doc.kind == DocKind.video
                    ? const VideoSync(isTeacher: true)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}