import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:classcast_offline/models/sync_event.dart';
import 'package:classcast_offline/services/host/classcast_host.dart';
import 'package:classcast_offline/services/sync_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

/// A classroom at size.
///
/// Everything else in the suite proves one thing at a time on one connection.
/// This one fills a room: dozens of phones joining, heartbeating, following the
/// class page and leaving, all against the real server, all at once. It is
/// where a per-student mistake stops being invisible — an O(n²) join, a socket
/// set that only ever grows, a roster frame that arrives for everyone but one.
///
/// It also measures, because "smooth" is a number: how long the whole class
/// takes to be on the roster, and how long a page change takes to reach every
/// phone in it. Those go to the console, which is the only place a load test
/// reports from.
///
/// Run bigger than CI does with:
///   CLASSCAST_STUDENTS=300 flutter test test/load_test.dart
void main() {
  final students = int.tryParse(
          Platform.environment['CLASSCAST_STUDENTS'] ?? '') ??
      60;

  late ClasscastHost host;
  late int port;

  setUp(() async {
    host = ClasscastHost.instance;
    final ok = await host.start(port: 0, advertisedIp: '127.0.0.1');
    expect(ok, isTrue, reason: 'the classroom server must bind a port');
    port = host.port;
  });

  tearDown(() => host.stop());

  Future<HttpClientResponse> send(String method, String path,
      [Map<String, dynamic>? body]) async {
    final client = HttpClient();
    final request =
        await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.contentType = ContentType.json;
    if (body != null) request.write(jsonEncode(body));
    return request.close();
  }

  Future<Map<String, dynamic>> json(HttpClientResponse r) async => Map<String,
      dynamic>.from(
          jsonDecode(await r.transform(utf8.decoder).join()) as Map);

  /// Polls a condition instead of awaiting a stream, so N sockets can be waited
  /// on together without a queue per socket.
  Future<void> waitFor(
    bool Function() done, {
    required String what,
    Duration limit = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(limit);
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out after ${limit.inSeconds}s waiting for $what');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('$students students join, follow the class, and leave cleanly',
      () async {
    const teacherKey = 'LOADKEY';
    final created = await json(await send('POST', '/api/session', {
      'id': 'CLASS-LOAD',
      'name': 'Load',
      'teacherKey': teacherKey,
    }));
    expect(created['ok'], isTrue);

    // The teacher's own socket: the only way it learns who is in the room.
    final teacher = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-LOAD&role=teacher&key=$teacherKey'));
    final teacherEvents = <SyncEvent>[];
    teacher.stream.listen((frame) {
      final event = SyncProtocol.decode(frame);
      if (event != null) teacherEvents.add(event);
    });
    addTearDown(() async {
      await teacher.sink.close();
    });

    // --- every phone joins at once ---
    final joinWatch = Stopwatch()..start();
    final phones = <_Phone>[];
    for (var i = 0; i < students; i++) {
      phones.add(_Phone(i, port));
    }
    // The probe and the session read every phone does before it can show
    // anything, all at the same time.
    await Future.wait(phones.map((p) async {
      final ping = await send('GET', '/api/ping');
      expect(ping.statusCode, 200, reason: 'phone ${p.index} could not probe');
      final snap = await send('GET', '/api/session?id=CLASS-LOAD');
      expect((await json(snap))['ok'], isTrue,
          reason: 'phone ${p.index} could not read the session');
      await p.connect();
    }));
    await waitFor(
      () => teacherEvents
          .where((e) => e.type == SyncEventType.participantJoined)
          .length >=
          students,
      what: 'all $students students on the teacher roster',
      limit: const Duration(seconds: 60),
    );
    joinWatch.stop();

    final joined = teacherEvents
        .where((e) => e.type == SyncEventType.participantJoined)
        .toList();
    expect(joined.length, students,
        reason: 'every joined phone has to be counted exactly once');
    // Ids are unique: two phones sharing one id would silently overwrite each
    // other in the roster and in take-control.
    expect(joined.map((e) => e.participantId).toSet().length, students,
        reason: 'each student needs their own seat');
    printOn('join: $students students on the roster in '
        '${joinWatch.elapsedMilliseconds}ms');

    // --- the teacher moves the class; every phone has to see it ---
    final pageWatch = Stopwatch()..start();
    await send('POST', '/api/page',
        {'teacherKey': teacherKey, 'page': 3, 'totalPages': 20});
    await waitFor(
      () => phones.every((p) => p.sawPage(3)),
      what: 'the class page to reach every phone',
      limit: const Duration(seconds: 30),
    );
    pageWatch.stop();
    printOn('sync: page 3 reached all $students phones in '
        '${pageWatch.elapsedMilliseconds}ms');

    // Heartbeats keep every seat warm. Three missed beats and the host drops a
    // student — so if this passes, the roster is not quietly emptying itself.
    await Future<void>.delayed(const Duration(seconds: 2));
    final before = teacherEvents.length;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(
      teacherEvents
          .where((e) => e.type == SyncEventType.participantLeft)
          .length,
      0,
      reason: 'a heartbeating phone must not lose its seat (frames: '
          '${teacherEvents.length - before})',
    );

    // The other half of the n²: no student is told who else is in the room.
    // Nothing renders another student's name, so those frames were pure cost —
    // and on a hotspot they compete with the document for the same radio.
    final rosterNoise = phones
        .map((p) => p.events
            .where((e) => e.type == SyncEventType.participantJoined)
            .length)
        .fold<int>(0, (a, b) => a + b);
    expect(rosterNoise, 0,
        reason: 'roster events belong to the teacher alone');

    // --- the shared file, N downloads at once ---
    final dir = Directory.systemTemp.createTempSync('load');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bytes = List<int>.filled(256 * 1024, 7);
    final file = File('${dir.path}/deck.pdf')..writeAsBytesSync(bytes);
    host.registerDocument('deck.pdf', file.path);
    final shared = await json(await send('POST', '/api/document', {
      'teacherKey': teacherKey,
      'documentName': 'deck.pdf',
      'totalPages': 20,
    }));
    final target = Uri.parse((shared['session'] as Map)['documentUrl'] as String);

    final downloadWatch = Stopwatch()..start();
    final downloads = await Future.wait(phones.map((p) async {
      final client = HttpClient();
      final request = await client.openUrl(
          'GET', Uri.parse('http://127.0.0.1:$port${target.path}?${target.query}'));
      final res = await request.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      return res.statusCode == 200 && body.length == bytes.length;
    }));
    downloadWatch.stop();
    expect(downloads.every((ok) => ok), isTrue,
        reason: 'every phone has to be able to take the file');
    printOn('file: $students concurrent downloads in '
        '${downloadWatch.elapsedMilliseconds}ms');

    // --- take control reaches the whole room, once ---
    await send('POST', '/api/take-control', {'teacherKey': teacherKey});
    await waitFor(
      () => phones.every((p) => p.sawTakeControl),
      what: 'take control to reach every phone',
      limit: const Duration(seconds: 30),
    );

    // --- and everyone leaves ---
    await Future.wait(phones.map((p) => p.close()));
    await waitFor(
      () => teacherEvents
              .where((e) => e.type == SyncEventType.participantLeft)
              .length >=
          students,
      what: 'every departure to reach the teacher',
      limit: const Duration(seconds: 60),
    );

    // A fresh teacher socket proves the roster is really empty, not just that
    // the leave frames went out: nothing may be left behind to be replayed to
    // the next lesson.
    final fresh = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-LOAD&role=teacher&key=$teacherKey'));
    final freshEvents = <SyncEvent>[];
    fresh.stream.listen((frame) {
      final event = SyncProtocol.decode(frame);
      if (event != null) freshEvents.add(event);
    });
    addTearDown(() async {
      await fresh.sink.close();
    });
    await waitFor(
      () => freshEvents.isNotEmpty,
      what: 'the reconnected teacher socket to be greeted',
      limit: const Duration(seconds: 10),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(
      freshEvents
          .where((e) => e.type == SyncEventType.participantJoined)
          .length,
      0,
      reason: 'a departed student must not be replayed to the next class',
    );
    printOn('teardown: $students sockets closed, roster clean');
  });
}

/// One simulated phone: a socket, the frames it has seen, and the heartbeat a
/// real client sends on a timer.
class _Phone {
  _Phone(this.index, this.port);

  final int index;
  final int port;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;

  /// Every frame this phone has received, kept so the test can ask about it
  /// without a queue per socket.
  final events = <SyncEvent>[];

  bool sawPage(int page) =>
      events.any((e) => e.type == SyncEventType.pageChanged && e.page == page);

  bool get sawTakeControl =>
      events.any((e) => e.type == SyncEventType.takeControl);

  Future<void> connect() async {
    final channel = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-LOAD&name=Phone$index&device=Android'));
    _channel = channel;
    _sub = channel.stream.listen((frame) {
      final event = SyncProtocol.decode(frame);
      if (event != null) events.add(event);
    });
    channel.sink.add(SyncProtocol.encode(SyncEvent(
      type: SyncEventType.join,
      sessionId: 'CLASS-LOAD',
      participantName: 'Phone$index',
    )));
    // The client's own timer, shortened so a load test does not have to run
    // for half a minute to prove heartbeats work.
    _heartbeat = Timer.periodic(const Duration(milliseconds: 500), (_) {
      try {
        channel.sink.add(SyncProtocol.encode(SyncEvent(
          type: SyncEventType.heartbeat,
          sessionId: 'CLASS-LOAD',
          participantName: 'Phone$index',
        )));
      } catch (_) {/* the socket went away mid-test */}
    });
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    await _sub?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {/* already gone */}
    _channel = null;
  }
}

/// Load numbers belong in the log, where CI keeps them.
void printOn(String line) {
  // ignore: avoid_print
  print('[load] $line');
}