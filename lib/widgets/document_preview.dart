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

/// The teacher's selection: the student's three values plus the view mode.
DocumentPreviewKey _sessionKey(SessionProvider sessions, OfficeViewMode mode) =>
    DocumentPreviewKey(
      documentId: sessions.active?.documentId,
      page: sessions.active?.page ?? 1,
      total: sessions.active?.totalPages ?? 0,
      mode: mode,
    );

/// The student's selection: same three values, no view mode.
DocumentPreviewKey _syncKey(SyncProvider sync) => DocumentPreviewKey(
      documentId: sync.snapshot?.documentId,
      page: sync.snapshot?.page ?? 1,
      total: sync.snapshot?.totalPages ?? 0,
    );

/// Builds [builder] again only when [keyOf] returns something different.
///
/// This is `Selector`'s job, done by hand. `Selector` and `buildWhen` were both
/// tried here and both rejected by the analyzer for reasons that were not worth
/// fighting, and this has one advantage over both: the widget it hands back is
/// the *same instance* when nothing moved, so the document subtree is not
/// rebuilt at all rather than rebuilt to the same thing.
class _PreviewGate<T extends Object> extends StatefulWidget {
  final DocumentPreviewKey Function(T value) keyOf;
  final Widget Function(BuildContext context, T value) builder;

  const _PreviewGate({required this.keyOf, required this.builder});

  @override
  State<_PreviewGate<T>> createState() => _PreviewGateState<T>();
}

class _PreviewGateState<T extends Object> extends State<_PreviewGate<T>> {
  DocumentPreviewKey? _key;
  Widget? _child;

  @override
  Widget build(BuildContext context) {
    return Consumer<T>(
      builder: (context, value, _) {
        final key = widget.keyOf(value);
        if (_child == null || _key != key) {
          _key = key;
          _child = widget.builder(context, value);
        }
        return _child!;
      },
    );
  }
}

/// The teacher's document panel.
///
/// Rebuilds only when the shared file changes, the page moves, the real page
/// count arrives, or the teacher switches between one-page-at-a-time and
/// scrolling.
class SessionDocumentPreview extends StatelessWidget {
  final OfficeViewMode viewMode;

  /// Given the session, build the document. The page comes out of the key.
  final Widget Function(BuildContext context, SessionProvider sessions)
      builder;

  const SessionDocumentPreview({
    super.key,
    required this.viewMode,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return _PreviewGate<SessionProvider>(
      keyOf: (sessions) => _sessionKey(sessions, viewMode),
      builder: (context, sessions) =>
          builder(context, sessions.active?.page ?? 1),
    );
  }
}

/// The student's document panel.
///
/// Same short list. The snapshot is taken from the value the gate was handed,
/// so this can never draw a page older than the one that was selected, and
/// never has to force-unwrap a snapshot that has since gone.
class SyncDocumentPreview extends StatelessWidget {
  final Widget Function(BuildContext context, ClassroomSession snapshot)
      builder;

  const SyncDocumentPreview({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return _PreviewGate<SyncProvider>(
      keyOf: _syncKey,
      builder: (context, sync) {
        final snapshot = sync.snapshot;
        if (snapshot == null) return const SizedBox.shrink();
        return builder(context, snapshot);
      },
    );
  }
}
