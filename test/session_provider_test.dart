
import 'package:classcast_offline/models/sync_event.dart';
import 'package:classcast_offline/providers/session_provider.dart';
import 'package:classcast_offline/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory store, so these tests exercise the real provider without SQLite.
class _MemoryStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  late SessionProvider sessions;

  setUp(() {
    setLocalStoreOverride(_MemoryStore());
    sessions = SessionProvider();
  });

  tearDown(() async {
    sessions.dispose();
    setLocalStoreOverride(null);
  });

  test('refreshing stored sessions leaves the live roster alone', () async {
    await sessions.createSession(name: 'Physics', subject: 'Optics');
    sessions.applyEvent(_joined(sessions, 'stu-1', 'Ana'));

    expect(sessions.participants.map((p) => p.name), ['Ana']);

    // load() used to clear _participants, so tapping Refresh on the Students
    // screen made every connected student vanish for the rest of the lesson.
    await sessions.load();

    expect(sessions.participants.map((p) => p.name), ['Ana']);
    expect(sessions.connectedCount, 1);
  });

  test('a raised hand and a reported page reach the teacher', () async {
    await sessions.createSession(name: 'Physics');
    sessions.applyEvent(_joined(sessions, 'stu-1', 'Ana'));
    sessions.applyEvent(SyncEvent(
      type: SyncEventType.handRaised,
      sessionId: sessions.active!.id,
      participantId: 'stu-1',
      participantName: 'Ana',
    ));
    sessions.applyEvent(SyncEvent(
      type: SyncEventType.studentPageChanged,
      sessionId: sessions.active!.id,
      participantId: 'stu-1',
      participantName: 'Ana',
      page: 4,
    ));

    expect(sessions.raisedHands.keys, contains('stu-1'));
    expect(sessions.studentPages['stu-1'], 4);
  });

  test('a page change clamps to the real total', () async {
    await sessions.createSession(name: 'Physics');
    // The total only arrives with a document, which is how the teacher
    // actually learns it: the file is opened and counted.
    sessions.applyEvent(SyncEvent(
      type: SyncEventType.documentChanged,
      sessionId: sessions.active!.id,
      documentId: 'doc-1',
      documentName: 'lesson.pptx',
      totalPages: 3,
    ));
    sessions.applyEvent(SyncEvent(
      type: SyncEventType.pageChanged,
      sessionId: sessions.active!.id,
      page: 99,
    ));

    expect(sessions.active!.totalPages, 3);
    expect(sessions.active!.page, 3);
  });

  test('ending a session clears the roster', () async {
    await sessions.createSession(name: 'Physics');
    sessions.applyEvent(_joined(sessions, 'stu-1', 'Ana'));
    expect(sessions.participants, hasLength(1));

    await sessions.endSession();

    expect(sessions.participants, isEmpty);
    expect(sessions.active, isNull);
  });
}

/// A student joining the session that is actually running — applyEvent drops
/// anything for another session id, which is what made an earlier version of
/// this file pass the wrong way round.
SyncEvent _joined(SessionProvider sessions, String id, String name) => SyncEvent(
      type: SyncEventType.participantJoined,
      sessionId: sessions.active!.id,
      participantId: id,
      participantName: name,
    );
