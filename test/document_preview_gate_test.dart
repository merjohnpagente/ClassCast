import 'package:classcast_offline/models/classroom_session.dart';
import 'package:classcast_offline/providers/session_provider.dart';
import 'package:classcast_offline/providers/sync_provider.dart';
import 'package:classcast_offline/widgets/document_preview.dart';
import 'package:classcast_offline/widgets/office/office_document_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The gate that decides when the document is rebuilt.
///
/// It exists to keep a raised hand from rebuilding a two-thousand-cell
/// spreadsheet, which means it has to be exactly as picky about what matters as
/// it is about what does not. Video is the case it got wrong: playback was not
/// part of the key, so the subtree stayed identical while a recording played
/// and every student watched it sitting still.
class _FakeSync extends SyncProvider {
  ClassroomSession? _snapshot;

  @override
  ClassroomSession? get snapshot => _snapshot;

  void publish(ClassroomSession next) {
    _snapshot = next;
    notifyListeners();
  }
}

class _FakeSessions extends SessionProvider {
  ClassroomSession? _active;

  @override
  ClassroomSession? get active => _active;

  void publish(ClassroomSession next) {
    _active = next;
    notifyListeners();
  }
}

void main() {
  ClassroomSession sessionWith({
    int videoPositionMs = 0,
    bool videoPlaying = false,
    String? documentUrl = 'http://192.168.43.1:8080/files/lesson.mp4?t=abc',
  }) =>
      ClassroomSession(
        id: 'CLASS-1',
        name: 'Class',
        createdAt: DateTime(2026),
        isActive: true,
        documentId: 'doc-1',
        documentName: 'lesson.mp4',
        documentUrl: documentUrl,
        page: 1,
        totalPages: 0,
        videoPositionMs: videoPositionMs,
        videoPlaying: videoPlaying,
      );

  testWidgets('a playing video rebuilds the student panel', (tester) async {
    final sync = _FakeSync();
    var builds = 0;
    sync.publish(sessionWith());
    await tester.pumpWidget(
      ChangeNotifierProvider<SyncProvider>.value(
        value: sync,
        child: MaterialApp(
          home: SyncDocumentPreview(
            builder: (context, snapshot) {
              builds++;
              return Text('at ${snapshot.videoPositionMs}',
                  textDirection: TextDirection.ltr);
            },
          ),
        ),
      ),
    );
    expect(builds, 1);

    // The teacher plays. Nothing on the student's screen moves without this.
    sync.publish(sessionWith(videoPositionMs: 5000, videoPlaying: true));
    await tester.pump();
    expect(builds, 2, reason: 'a class that is playing has to be redrawn');
    expect(find.text('at 5000'), findsOneWidget);

    // And a seek is its own redraw.
    sync.publish(sessionWith(videoPositionMs: 90000, videoPlaying: true));
    await tester.pump();
    expect(builds, 3);
    expect(find.text('at 90000'), findsOneWidget);
  });

  testWidgets('an unchanged video does not rebuild the student panel',
      (tester) async {
    // The whole point of the gate: a roster update or a raised hand must not
    // drag the document along.
    final sync = _FakeSync();
    var builds = 0;
    sync.publish(sessionWith(videoPositionMs: 5000, videoPlaying: true));
    await tester.pumpWidget(
      ChangeNotifierProvider<SyncProvider>.value(
        value: sync,
        child: MaterialApp(
          home: SyncDocumentPreview(
            builder: (context, snapshot) {
              builds++;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(builds, 1);

    sync.publish(sessionWith(videoPositionMs: 5000, videoPlaying: true));
    await tester.pump();
    expect(builds, 1, reason: 'nothing the document reads has moved');
  });

  testWidgets('the same file at a new address rebuilds the student panel',
      (tester) async {
    // A classroom that moved networks re-announces the same document at a new
    // address; a panel holding the old one would fetch from an address that no
    // longer exists.
    final sync = _FakeSync();
    var builds = 0;
    sync.publish(sessionWith());
    await tester.pumpWidget(
      ChangeNotifierProvider<SyncProvider>.value(
        value: sync,
        child: MaterialApp(
          home: SyncDocumentPreview(
            builder: (context, snapshot) {
              builds++;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(builds, 1);

    sync.publish(sessionWith(documentUrl: 'http://192.168.1.24:8080/f.mp4?t=z'));
    await tester.pump();
    expect(builds, 2);
  });

  testWidgets("the teacher's panel follows the video too", (tester) async {
    final sessions = _FakeSessions();
    var builds = 0;
    sessions.publish(sessionWith());
    await tester.pumpWidget(
      ChangeNotifierProvider<SessionProvider>.value(
        value: sessions,
        child: MaterialApp(
          home: SessionDocumentPreview(
            viewMode: OfficeViewMode.pages,
            builder: (context, provider) {
              builds++;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(builds, 1);

    sessions.publish(sessionWith(videoPositionMs: 4200, videoPlaying: true));
    await tester.pump();
    expect(builds, 2,
        reason: 'the teacher\'s own bar shows what the class is watching');
  });
}