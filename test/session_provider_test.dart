
import 'package:classcast_offline/models/sync_event.dart';
import 'package:classcast_offline/providers/session_provider.dart';
import 'package:classcast_offline/services/host/classcast_host.dart';
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
    // Each test runs its own classroom. Leaving the host up kept the previous
    // test's session registered, and the next createSession's teacher socket
    // was then refused by a host that still belonged to the last test.
    await ClasscastHost.instance.stop();
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

  test('ending a session forgets hands and reported pages too', () async {
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
    expect(sessions.raisedHands, isNotEmpty);
    expect(sessions.studentPages, isNotEmpty);

    await sessions.endSession();

    // Left behind, these attached themselves to the next session's roster ids
    // and showed badges for students who were never in the room.
    expect(sessions.raisedHands, isEmpty);
    expect(sessions.studentPages, isEmpty);
  });

  test('a fresh session does not doubt the network yet', () async {
    // The loopback address keeps the teacher's own control calls on this
    // machine, so the test does not depend on the runner's LAN interface.
    await sessions.createSession(name: 'Physics', hostIp: '127.0.0.1');

    expect(sessions.reachabilityHintDue, isFalse);
  });

  test('a live session with no joins raises the hint after the window',
      () async {
    sessions.reachabilityHintAfter = const Duration(milliseconds: 40);
    await sessions.createSession(name: 'Physics', hostIp: '127.0.0.1');

    await Future<void>.delayed(const Duration(milliseconds: 90));

    expect(sessions.reachabilityHintDue, isTrue);
  });

  test('the first student join clears the reachability hint', () async {
    sessions.reachabilityHintAfter = const Duration(milliseconds: 40);
    await sessions.createSession(name: 'Physics', hostIp: '127.0.0.1');
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(sessions.reachabilityHintDue, isTrue);

    sessions.applyEvent(_joined(sessions, 'stu-1', 'Ana'));

    // A student who joins and later leaves still proves the network lets
    // students through, so the hint must not come back.
    expect(sessions.reachabilityHintDue, isFalse);
  });

  test('ending resets the hint clock for the next session', () async {
    sessions.reachabilityHintAfter = const Duration(milliseconds: 40);
    await sessions.createSession(name: 'Physics', hostIp: '127.0.0.1');
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(sessions.reachabilityHintDue, isTrue);

    await sessions.endSession();
    await sessions.createSession(name: 'Chemistry', hostIp: '127.0.0.1');

    expect(sessions.reachabilityHintDue, isFalse);
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
