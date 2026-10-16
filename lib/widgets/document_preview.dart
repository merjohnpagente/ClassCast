import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/classroom_session.dart';
import '../providers/session_provider.dart';
import '../providers/sync_provider.dart';
import 'office/office_document_scroll_view.dart';

/// What the document subtree actually depends on.
///
/// There was no granular listening anywhere in this app, so both presentation
/// screens rebuilt the document every time anything at all moved — and the
/// document is the most expensive thing either of them draws. This is the
/// short list of values the document is a function of, and comparing it is what
/// keeps a raised hand or a page report from dragging a spreadsheet page of two
/// thousand cells behind it.
///
/// A record would have done the same job, but it does not survive being used as
/// a `Selector`'s selected type without inference help, and a named class with
/// `==` is easier to read here anyway.
@immutable
class DocumentPreviewKey {
  final String? documentId;
  final int page;
  final int total;

  /// Anything else the document reads that is not part of the session — the
  /// teacher's view mode today. Kept `Object?` so this file does not have to
  /// know what it might hold later.
  final Object? mode;

  const DocumentPreviewKey({
    this.documentId,
    required this.page,
    required this.total,
    this.mode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentPreviewKey &&
          other.documentId == documentId &&
          other.page == page &&
          other.total == total &&
          other.mode == mode;

  @override
  int get hashCode => Object.hash(documentId, page, total, mode);
}

/// The teacher's document panel.
///
/// Rebuilds only when the shared file changes, the page moves, the real page
/// count arrives, or the teacher switches between one-page-at-a-time and
/// scrolling.
class SessionDocumentPreview extends StatelessWidget {
  final OfficeViewMode viewMode;

  /// Given the page the class is on, build the document.
  final Widget Function(BuildContext context, int page) builder;

  const SessionDocumentPreview({
    super.key,
    required this.viewMode,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<SessionProvider, DocumentPreviewKey>(
      selector: (_, sessions) => DocumentPreviewKey(
        documentId: sessions.active?.documentId,
        page: sessions.active?.page ?? 1,
        total: sessions.active?.totalPages ?? 0,
        mode: viewMode,
      ),
      builder: (context, key) => builder(context, key.page),
    );
  }
}

/// The student's document panel.
///
/// Same short list. The snapshot is read fresh inside the builder rather than
/// captured from the enclosing build, so this can never draw a stale page — and
/// never has to force-unwrap a snapshot that has since gone.
class SyncDocumentPreview extends StatelessWidget {
  final Widget Function(BuildContext context, ClassroomSession snapshot)
      builder;

  const SyncDocumentPreview({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return Selector<SyncProvider, DocumentPreviewKey>(
      selector: (_, sync) => DocumentPreviewKey(
        documentId: sync.snapshot?.documentId,
        page: sync.snapshot?.page ?? 1,
        total: sync.snapshot?.totalPages ?? 0,
      ),
      builder: (context, _) {
        final snapshot = context.read<SyncProvider>().snapshot;
        if (snapshot == null) return const SizedBox.shrink();
        return builder(context, snapshot);
      },
    );
  }
}
