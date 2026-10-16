import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:classcast_offline/models/sync_event.dart';
import 'package:classcast_offline/services/host/classcast_host.dart';
import 'package:classcast_offline/services/sync_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

/// The whole student path, against the real classroom server.
///
/// Every step a student's phone takes, in order: probe, fetch the session,
/// open the socket, register, then follow the teacher. A classroom where the
/// teacher can see a connected student is only true if all of this works, so
/// it is tested as one flow rather than endpoint by endpoint.
void main() {
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

  test('a student can join and follow the class page', () async {
    const teacherKey = 'TEACHKEY';

    // 1. The teacher starts a session on their own phone.
    final created = await json(await send('POST', '/api/session', {
      'id': 'CLASS-E2E',
      'name': 'Physics',
      'teacherKey': teacherKey,
    }));
    expect(created['ok'], isTrue);
    final sessionId = (created['session'] as Map)['id'] as String;
    expect(sessionId, 'CLASS-E2E');

    // 2. The student's phone probes the address in the QR.
    final ping = await send('GET', '/api/ping');
    expect(ping.statusCode, 200);

    // 3. Fetches the session it is about to join.
    final snap = await json(await send('GET', '/api/session?id=$sessionId'));
    expect(snap['ok'], isTrue);

    // 4. Opens the live socket, which is what makes them count as connected.
    final student = IOWebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:$port/ws?session=$sessionId&name=Ana&device=Android'),
    );
    final inbox = StreamQueue<dynamic>(student.stream);
    addTearDown(() async {
      inbox.cancel();
      await student.sink.close();
    });

    // The host greets a new socket with the current state.
    final hello = SyncProtocol.decode(await inbox.next);
    expect(hello, isNotNull);
    expect(hello!.sessionId, sessionId);

    // 5. Says hello, so the teacher sees a name.
    student.sink.add(SyncProtocol.encode(SyncEvent(
      type: SyncEventType.join,
      sessionId: sessionId,
      participantName: 'Ana',
    )));

    // 6. The teacher moves to page 4; the student must receive it.
    final moved = await send('POST', '/api/page', {
      'teacherKey': teacherKey,
      'page': 4,
      'totalPages': 10,
    });
    expect(moved.statusCode, 200);

    // The socket also carries the re-greeting and the join announcement, so
    // wait for the frame that actually carries the class page. Matching on the
    // value rather than "has a page" matters: the opening snapshot already has
    // page 1, and matching that proved nothing.
    final relayed = await inbox.nextWhere(
      (frame) => SyncProtocol.decode(frame)?.page == 4,
      const Duration(seconds: 3),
    );
    final event = SyncProtocol.decode(relayed);
    expect(event, isNotNull, reason: 'the student socket must carry the page');
    expect(event!.sessionId, sessionId);
    expect(event.page, 4, reason: 'the class page has to reach the student');
  });

  test('a student receives the shared document and can load it', () async {
    const teacherKey = 'DOCKEY';
    await send('POST', '/api/session',
        {'id': 'CLASS-DOC', 'teacherKey': teacherKey});

    // The teacher's picked file, standing in for a real one.
    final dir = Directory.systemTemp.createTempSync('e2e');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/lesson.pdf')..writeAsStringSync('%PDF-1.4 e2e');
    host.registerDocument('lesson.pdf', file.path);
    await send('POST', '/api/document', {
      'teacherKey': teacherKey,
      'documentName': 'lesson.pdf',
      'totalPages': 3,
    });

    // This is exactly what the student's phone does on join.
    final snap = await json(await send('GET', '/api/session?id=CLASS-DOC'));
    final documentUrl = (snap['session'] as Map)['documentUrl'] as String;
    expect(documentUrl, contains('lesson.pdf'));

    // ...and then fetches it.
    final target = Uri.parse(documentUrl);
    final bytes = await send('GET', '${target.path}?${target.query}');
    expect(bytes.statusCode, 200);
    expect(await bytes.transform(utf8.decoder).join(), '%PDF-1.4 e2e');
  });

  test('a student cannot take the class page', () async {
    await send('POST', '/api/session', {
      'id': 'CLASS-SAFE',
      'teacherKey': 'OWNER',
    });

    // No teacher key: the control endpoints must refuse.
    final noKey = await send('POST', '/api/page', {'page': 9});
    expect(noKey.statusCode, 403);

    // A student socket cannot become the teacher just by asking.
    final impostor = await send('GET', '/ws?session=CLASS-SAFE&role=teacher');
    expect(impostor.statusCode, 403);
  });

  // A raised hand that the teacher never sees is a broken feature, and it was
  // broken silently: the host switched on 'raise_hand' while the client had
  // always sent 'hand_raised', so every frame fell through to a bare
  // `default: return` and nothing anywhere said so.
  test('a raised hand reaches the teacher', () async {
    const teacherKey = 'HANDKEY';
    await send('POST', '/api/session', {
      'id': 'CLASS-HAND',
      'teacherKey': teacherKey,
    });

    // The teacher's own socket, subscribed to events but not on the roster.
    final teacher = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-HAND&role=teacher&key=$teacherKey'));
    final teacherInbox = StreamQueue<dynamic>(teacher.stream);
    addTearDown(() async {
      await teacherInbox.cancel();
      await teacher.sink.close();
    });
    await teacherInbox.next; // the greeting

    final student = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-HAND&name=Ana&device=Android'));
    final studentInbox = StreamQueue<dynamic>(student.stream);
    addTearDown(() async {
      await studentInbox.cancel();
      await student.sink.close();
    });
    await studentInbox.next; // the greeting

    // Exactly what SyncProvider.setHandRaised(true) puts on the wire.
    student.sink.add(SyncProtocol.encode(SyncEvent(
      type: SyncEventType.handRaised,
      sessionId: 'CLASS-HAND',
      participantName: 'Ana',
    )));

    final relayed = await teacherInbox.nextWhere(
      (frame) => SyncProtocol.decode(frame)?.type == SyncEventType.handRaised,
      const Duration(seconds: 3),
    );
    final event = SyncProtocol.decode(relayed)!;
    expect(event.participantName, 'Ana',
        reason: 'the teacher has to know who wants attention');

    student.sink.add(SyncProtocol.encode(SyncEvent(
      type: SyncEventType.handLowered,
      sessionId: 'CLASS-HAND',
      participantName: 'Ana',
    )));
    await teacherInbox.nextWhere(
      (frame) => SyncProtocol.decode(frame)?.type == SyncEventType.handLowered,
      const Duration(seconds: 3),
    );

    // And a student browsing ahead reports where they went.
    student.sink.add(SyncProtocol.encode(SyncEvent(
      type: SyncEventType.studentPageChanged,
      sessionId: 'CLASS-HAND',
      participantName: 'Ana',
      page: 7,
    )));
    final page = await teacherInbox.nextWhere(
      (frame) =>
          SyncProtocol.decode(frame)?.type == SyncEventType.studentPageChanged,
      const Duration(seconds: 3),
    );
    expect(SyncProtocol.decode(page)!.page, 7);
  });

  // This route did not exist on this host, so "Sync all" and the per-student
  // "Take control" button both came back 404 — and a 404 is what flips the
  // app's status chip to a red "Not sharing", so the failure looked like the
  // whole classroom had gone rather than like one missing button.
  test('take control pulls a student back, and needs the key', () async {
    const teacherKey = 'CTRLKEY';
    await send('POST', '/api/session', {
      'id': 'CLASS-CTRL',
      'teacherKey': teacherKey,
    });

    final student = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-CTRL&name=Ana&device=Android'));
    final studentInbox = StreamQueue<dynamic>(student.stream);
    addTearDown(() async {
      await studentInbox.cancel();
      await student.sink.close();
    });
    await studentInbox.next; // the greeting

    // No key: still refused, like every other control route.
    final refused = await send('POST', '/api/take-control', {});
    expect(refused.statusCode, 403);

    final ok = await send('POST', '/api/take-control', {
      'teacherKey': teacherKey,
    });
    expect(ok.statusCode, 200);
    final body = await json(ok);
    expect(body['ok'], isTrue);
    expect(body['notified'], 1,
        reason: 'the one connected student has to be told');

    final relayed = await studentInbox.nextWhere(
      (frame) => SyncProtocol.decode(frame)?.type == SyncEventType.takeControl,
      const Duration(seconds: 3),
    );
    expect(SyncProtocol.decode(relayed), isNotNull,
        reason: 'take control has to reach the student');
  });
}

/// Minimal queue over a socket stream, so a test can await frames in order
/// without pulling in a package.
///
/// Frames that arrive while nobody is waiting are kept, not dropped — which is
/// the whole point of a queue, and the reason an earlier version of this file
/// timed out waiting for a broadcast it had silently thrown away.
class StreamQueue<T> {
  StreamQueue(Stream<T> stream) {
    _subscription = stream.listen(_push, onError: (Object error, StackTrace stack) {
      final pending = _pending;
      _pending = null;
      if (pending != null && !pending.isCompleted) {
        pending.completeError(error, stack);
      }
    });
  }

  final List<T> _items = [];
  StreamSubscription<T>? _subscription;
  Completer<T>? _pending;

  void _push(T event) {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      _pending = null;
      pending.complete(event);
      return;
    }
    _items.add(event);
  }

  Future<T> get next {
    if (_items.isNotEmpty) return Future<T>.value(_items.removeAt(0));
    final completer = Completer<T>();
    _pending = completer;
    return completer.future;
  }

  /// The next frame matching [test], skipping the ones that do not.
  Future<T> nextWhere(
    bool Function(T frame) test,
    Duration limit,
  ) async {
    final deadline = DateTime.now().add(limit);
    while (true) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        throw TimeoutException('No matching frame within $limit', limit);
      }
      final frame = await next.timeout(remaining);
      if (test(frame)) return frame;
    }
  }

  /// Stop listening, so a test can end without a live subscription.
  Future<void> cancel() async => _subscription?.cancel();
}
