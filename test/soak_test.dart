import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:classcast_offline/models/sync_event.dart';
import 'package:classcast_offline/services/host/classcast_host.dart';
import 'package:classcast_offline/services/sync_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

/// A class that runs for a long time.
///
/// A load test proves the room fills up and everyone is served. This one proves
/// the room *stays* correct: ten minutes of a teacher flipping pages, students
/// raising hands, a video being played and seeked, phones joining and leaving
/// while all of that happens — and then, at the end, that the host is back to
/// nothing. Leaks and silent drops only show up over time; that is the whole
/// reason this exists.
///
/// Skipped unless it is asked for, because ten minutes in everyone's test suite
/// is ten minutes of everyone's day:
///
///   CLASSCAST_SOAK=1 CLASSCAST_SOAK_MINUTES=10 CLASSCAST_SOAK_STUDENTS=100 \
///     flutter test test/soak_test.dart
///
/// `.github/workflows/soak.yml` does exactly that, on demand.
void main() {
  final soak = Platform.environment['CLASSCAST_SOAK'] == '1';
  final minutes =
      int.tryParse(Platform.environment['CLASSCAST_SOAK_MINUTES'] ?? '') ?? 10;
  final students =
      int.tryParse(Platform.environment['CLASSCAST_SOAK_STUDENTS'] ?? '') ?? 100;

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
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('$students students hold together for $minutes minutes', () async {
    const teacherKey = 'SOAKKEY';
    await send('POST', '/api/session', {
      'id': 'CLASS-SOAK',
      'name': 'Soak',
      'teacherKey': teacherKey,
    });
    final dir = Directory.systemTemp.createTempSync('soak');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/lesson.mp4')
      ..writeAsStringSync('fake-video-bytes' * 4096);
    host.registerDocument('lesson.mp4', file.path);
    await send('POST', '/api/document', {
      'teacherKey': teacherKey,
      'documentName': 'lesson.mp4',
      'totalPages': 40,
    });

    // The teacher's socket is the room's only witness.
    final teacher = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-SOAK&role=teacher&key=$teacherKey'));
    final teacherEvents = <SyncEvent>[];
    teacher.stream.listen((frame) {
      final event = SyncProtocol.decode(frame);
      if (event != null) teacherEvents.add(event);
    });
    addTearDown(() async {
      await teacher.sink.close();
    });
    await waitFor(() => teacherEvents.isNotEmpty, what: 'the teacher greeting');

    // Students arrive the way they really do: in ones and twos, spread over the
    // first minute, not all in the same millisecond.
    final phones = <_SoakPhone>[];
    for (var i = 0; i < students; i++) {
      if (i % 8 == 0) await Future<void>.delayed(const Duration(milliseconds: 300));
      final phone = _SoakPhone(i, port);
      phones.add(phone);
      await phone.connect();
    }

    int joinedCount() => teacherEvents
        .where((e) => e.type == SyncEventType.participantJoined)
        .length;
    int leftCount() => teacherEvents
        .where((e) => e.type == SyncEventType.participantLeft)
        .length;

    await waitFor(
      () => joinedCount() >= students,
      what: '$students students on the roster',
      limit: const Duration(seconds: 60),
    );
    expect(host.participantCount, students,
        reason: 'the host has to be counting exactly the phones that joined');
    expect(host.teacherSocketCount, 1,
        reason: 'exactly one roster subscriber: the teacher');
    report('filled up: $students students, '
        '${host.socketCount} sockets, ${rssInMb()}MB rss');

    // --- the long run ---
    final startedAt = DateTime.now();
    final until = startedAt.add(Duration(minutes: minutes));
    final rssAtStart = ProcessInfo.currentRss;
    var page = 1;
    var flips = 0;
    var videoFrames = 0;
    var hands = 0;
    var slowestPageMs = 0;
    var lostDuringRun = 0;
    var lastReport = DateTime.now();

    while (DateTime.now().isBefore(until)) {
      // The teacher works the room: a page every couple of seconds, a hand every
      // few, a video control now and then, take control occasionally.
      page = 1 + (page % 40);
      final flipWatch = Stopwatch()..start();
      await send('POST', '/api/page',
          {'teacherKey': teacherKey, 'page': page, 'totalPages': 40});
      flips++;
      await Future<void>.delayed(const Duration(milliseconds: 2000));

      // Every phone has to see the class page. A sample is enough to catch a
      // dropped socket, and checking all hundred every two seconds would make
      // the test the load rather than the server.
      await waitFor(
        () => phones.every((p) => p.sawPage(page)),
        what: 'page $page to reach every phone',
        limit: const Duration(seconds: 10),
      );
      final flipMs = flipWatch.elapsedMilliseconds;
      if (flipMs > slowestPageMs) slowestPageMs = flipMs;

      // A hand, raised and lowered: the noisiest thing on the wire per student.
      if (flips % 3 == 0) {
        final hander = phones[flips % phones.length];
        final before = hander.raisedHandCount;
        hander.raiseHand();
        hands++;
        await waitFor(
          () => hander.raisedHandCount > before,
          what: 'a raised hand to reach the teacher',
          limit: const Duration(seconds: 10),
        );
        hander.lowerHand();
      }

      if (flips % 7 == 0) {
        await send('POST', '/api/video', {
          'teacherKey': teacherKey,
          'positionMs': 30000 + flips * 1000,
          'playing': flips.isEven,
          'durationMs': 600000,
        });
        videoFrames++;
      }
      if (flips % 11 == 0) {
        await send('POST', '/api/take-control', {'teacherKey': teacherKey});
      }

      // Nobody may quietly vanish: every phone heartbeats, so a lost seat here
      // is a bug and not a departure.
      final left = leftCount();
      if (left != lostDuringRun) {
        lostDuringRun = left;
        fail('$left students lost their seat mid-lesson. A heartbeating phone '
            'is never dropped; this is the presence sweep or a dead socket.');
      }

      if (DateTime.now().difference(lastReport) >=
          const Duration(seconds: 30)) {
        lastReport = DateTime.now();
        report('${DateTime.now().difference(startedAt).inMinutes}m: '
            '$flips page flips, $hands hands, $videoFrames video frames, '
            'slowest full-class sync ${slowestPageMs}ms, '
            '${rssInMb()}MB rss, ${host.participantCount} present');
      }
    }

    // --- the room empties ---
    await Future.wait(phones.map((p) => p.close()));
    await waitFor(
      () => leftCount() >= students,
      what: 'every departure to reach the teacher',
      limit: const Duration(seconds: 60),
    );
    // The teacher leaves too: an empty room has no sockets left in it at all,
    // and that is the shape the next lesson starts from.
    await teacher.sink.close();
    await waitFor(
      () => host.socketCount == 0,
      what: 'the last socket to close',
      limit: const Duration(seconds: 30),
    );

    final rssAtEnd = ProcessInfo.currentRss;
    expect(host.participantCount, 0,
        reason: 'an emptied classroom must leave nobody behind');
    expect(host.socketCount, 0,
        reason: 'every socket must be closed, teacher included');
    expect(host.teacherSocketCount, 0,
        reason: 'a dead teacher socket must not stay subscribed to the roster');

    // Memory is the point of running this long: a socket or a participant that
    // is never released looks exactly like this. The bound is generous —
    // the test wants a runaway, not a warm-up.
    final growthMb = (rssAtEnd - rssAtStart) / (1024 * 1024);
    expect(growthMb, lessThan(192),
        reason: 'memory grew ${growthMb.toStringAsFixed(1)}MB over $minutes '
            'minutes of a full room');

    report('done: $flips flips, ${host.socketCount} sockets left, '
        'rss ${rssAtStart ~/ (1024 * 1024)}MB -> ${rssAtEnd ~/ (1024 * 1024)}MB '
        '(${growthMb.toStringAsFixed(1)}MB over $minutes minutes)');
  },
      skip: soak
          ? false
          : 'long soak — run with CLASSCAST_SOAK=1 (see the file header)');
}

/// One phone, kept open for the whole run.
class _SoakPhone {
  _SoakPhone(this.index, this.port);

  final int index;
  final int port;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _heartbeat;

  final events = <SyncEvent>[];

  bool sawPage(int page) => events
      .any((e) => e.type == SyncEventType.pageChanged && e.page == page);

  /// Counted rather than flagged: a hand raised again a minute later has to be
  /// seen arriving again, not satisfied by the one from before.
  int get raisedHandCount =>
      events.where((e) => e.type == SyncEventType.handRaised).length;

  Future<void> connect() async {
    final channel = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-SOAK&name=Phone$index&device=Android'));
    _channel = channel;
    _sub = channel.stream.listen((frame) {
      final event = SyncProtocol.decode(frame);
      if (event != null) events.add(event);
    });
    channel.sink.add(SyncProtocol.encode(SyncEvent(
      type: SyncEventType.join,
      sessionId: 'CLASS-SOAK',
      participantName: 'Phone$index',
      message: 'Android',
    )));
    // Two seconds rather than the client's ten: over a ten-minute run this
    // proves the presence sweep at five missed-beat intervals per phone.
    _heartbeat = Timer.periodic(const Duration(seconds: 2), (_) {
      _send(SyncEvent(
        type: SyncEventType.heartbeat,
        sessionId: 'CLASS-SOAK',
        participantName: 'Phone$index',
      ));
    });
  }

  void _send(SyncEvent event) {
    try {
      _channel?.sink.add(SyncProtocol.encode(event));
    } catch (_) {/* the socket went away; the test will notice */}
  }

  void raiseHand() => _send(SyncEvent(
        type: SyncEventType.handRaised,
        sessionId: 'CLASS-SOAK',
        participantName: 'Phone$index',
      ));

  void lowerHand() => _send(SyncEvent(
        type: SyncEventType.handLowered,
        sessionId: 'CLASS-SOAK',
        participantName: 'Phone$index',
      ));

  Future<void> close() async {
    _heartbeat?.cancel();
    await _sub?.cancel();
    try {
      await _channel?.sink.close();
    } catch (_) {/* already gone */}
    _channel = null;
  }
}

String rssInMb() =>
    (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(0);

/// Soak numbers belong in the log, which is where CI keeps them.
void report(String line) {
  // ignore: avoid_print
  print('[soak] $line');
}