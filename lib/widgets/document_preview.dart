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

  /// Where the file is fetched from. In the key because a classroom that moved
  /// networks re-announces the same document at a new address, and a panel
  /// holding the old one would fetch from an address that no longer exists.
  final String? documentUrl;

  /// Video playback. The class follows the teacher's position, and this gate
  /// decides whether the player is handed that position at all: without these
  /// two here the subtree stayed identical while a video played, and every
  /// student sat still while the teacher's recording moved.
  final int videoPositionMs;
  final bool videoPlaying;

  /// The teacher's freeze. Also has to be in the key: a freeze does not move
  /// the position or stop the clock, so without it the gate handed back the
  /// same player and a frozen class kept playing while the screen said
  /// "Paused".
  final bool videoFrozen;

  /// Anything else the document reads that is not part of the session — the
  /// teacher's view mode today. Kept `Object?` so this file does not have to
  /// know what it might hold later.
  final Object? mode;

  const DocumentPreviewKey({
    this.documentId,
    required this.page,
    required this.total,
    this.documentUrl,
    this.videoPositionMs = 0,
    this.videoPlaying = false,
    this.videoFrozen = false,
    this.mode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentPreviewKey &&
          other.documentId == documentId &&
          other.page == page &&
          other.total == total &&
          other.documentUrl == documentUrl &&
          other.videoPositionMs == videoPositionMs &&
          other.videoPlaying == videoPlaying &&
          other.videoFrozen == videoFrozen &&
          other.mode == mode;

  @override
  int get hashCode => Object.hash(documentId, page, total, documentUrl,
      videoPositionMs, videoPlaying, videoFrozen, mode);
}

/// The teacher's selection: the student's four values plus the view mode.
DocumentPreviewKey _sessionKey(SessionProvider sessions, OfficeViewMode mode) =>
    DocumentPreviewKey(
      documentId: sessions.active?.documentId,
      page: sessions.active?.page ?? 1,
      total: sessions.active?.totalPages ?? 0,
      documentUrl: sessions.active?.documentUrl,
      videoPositionMs: sessions.active?.videoPositionMs ?? 0,
      videoPlaying: sessions.active?.videoPlaying ?? false,
      videoFrozen: sessions.active?.syncPaused ?? false,
      mode: mode,
    );

/// The student's selection: same four values, plus whatever extra the student
/// screen varies the document by. That is its own page when the teacher allows
/// independent navigation: two students on different pages must not share one
/// cached subtree, and a student turning a page must see it turn.
DocumentPreviewKey _syncKey(SyncProvider sync, Object? mode) =>
    DocumentPreviewKey(
      documentId: sync.snapshot?.documentId,
      page: sync.snapshot?.page ?? 1,
      total: sync.snapshot?.totalPages ?? 0,
      documentUrl: sync.snapshot?.documentUrl,
      videoPositionMs: sync.snapshot?.videoPositionMs ?? 0,
      videoPlaying: sync.snapshot?.videoPlaying ?? false,
      // The same value the player receives as its freeze flag, from the same
      // provider, so the gate can never disagree with the player's own input.
      videoFrozen: sync.syncPaused,
      mode: mode,
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
      builder: (context, sessions) => builder(context, sessions),
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

  /// The page this screen draws, when it can differ from the class page.
  final Object? mode;

  const SyncDocumentPreview({super.key, required this.builder, this.mode});

  @override
  Widget build(BuildContext context) {
    return _PreviewGate<SyncProvider>(
      keyOf: (sync) => _syncKey(sync, mode),
      builder: (context, sync) {
        final snapshot = sync.snapshot;
        if (snapshot == null) return const SizedBox.shrink();
        return builder(context, snapshot);
      },
    );
  }
}
