import 'package:classcast_offline/models/classroom_session.dart';
import 'package:classcast_offline/providers/app_state.dart';
import 'package:classcast_offline/providers/sync_provider.dart';
import 'package:classcast_offline/screens/student/student_shell.dart';
import 'package:classcast_offline/screens/student/viewer_screen.dart';
import 'package:classcast_offline/services/classcast_client.dart';
import 'package:classcast_offline/services/local_store.dart';
import 'package:classcast_offline/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A SyncProvider that answers from memory.
///
/// The shell only ever reads [link] and [snapshot] from it — where the student
/// is and what the teacher has shared — so overriding those two is enough to
/// put the UI into any classroom state without opening a socket.
class _MemorySyncProvider extends SyncProvider {
  LinkState _memoryLink = LinkState.idle;
  ClassroomSession? _memorySnapshot;

  @override
  LinkState get link => _memoryLink;

  @override
  ClassroomSession? get snapshot => _memorySnapshot;

  /// The student is in the class; nothing has been shared yet.
  void joinWithoutASocket({required String sessionId, required String name}) {
    _memoryLink = LinkState.live;
    _memorySnapshot = ClassroomSession(
      id: sessionId,
      name: name,
      hostIp: '127.0.0.1',
      port: 8080,
      createdAt: DateTime.now(),
      isActive: true,
    );
    notifyListeners();
  }

  /// The teacher starts presenting.
  void shareDocument() {
    _memorySnapshot = _memorySnapshot!.copyWith(
      documentId: () => 'doc-lesson',
      documentName: () => 'lesson.png',
      documentUrl: () => 'http://127.0.0.1:8080/files/lesson.png?token=x',
      page: 1,
      totalPages: 1,
    );
    notifyListeners();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setLocalStoreOverride(PrefsLocalStore());
  });

  tearDown(() => setLocalStoreOverride(null));

  testWidgets(
      'a student who joined before the teacher shared anything advances '
      'from the waiting room to the viewer when the document arrives',
      (tester) async {
    final sync = _MemorySyncProvider();
    addTearDown(sync.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>(create: (_) => AppState()),
          ChangeNotifierProvider<SyncProvider>.value(value: sync),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const StudentShell(),
        ),
      ),
    );
    await tester.pump();

    sync.joinWithoutASocket(sessionId: 'CLASS-WAIT', name: 'Physics');
    await tester.pump();

    // The student opens the Viewer tab while nothing is shared yet. This is
    // the state they used to be parked in: the waiting room was built once,
    // kept forever, and the teacher sharing a file changed nothing on screen.
    await tester.tap(find.text('Viewer'));
    await tester.pump();
    expect(
      find.text('Please wait while the teacher starts the presentation.'),
      findsOneWidget,
    );
    expect(find.byType(StudentViewerScreen), findsNothing);

    // The teacher starts presenting.
    sync.shareDocument();
    await tester.pump();

    expect(
      find.byType(StudentViewerScreen),
      findsOneWidget,
      reason: 'the shared document must replace the waiting room by itself',
    );
    expect(
      find.text('Please wait while the teacher starts the presentation.'),
      findsNothing,
    );
  });
}
