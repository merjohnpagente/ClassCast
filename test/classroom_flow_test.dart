import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:classcast_offline/models/sync_event.dart';
import 'package:classcast_offline/providers/sync_provider.dart';
import 'package:classcast_offline/services/classcast_client.dart';
import 'package:classcast_offline/services/document_download.dart';
import 'package:classcast_offline/services/host/classcast_host.dart';
import 'package:classcast_offline/services/network_service.dart';
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

  test('a teacher socket that reconnects still gets the whole roster',
      () async {
    const teacherKey = 'ROSTERKEY';
    await send('POST', '/api/session', {
      'id': 'CLASS-ROSTER',
      'teacherKey': teacherKey,
    });

    final student = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-ROSTER&name=Ana&device=Android'));
    final studentInbox = StreamQueue<dynamic>(student.stream);
    addTearDown(() async {
      await studentInbox.cancel();
      await student.sink.close();
    });
    await studentInbox.next; // the greeting

    // The teacher's socket only opens after Ana is already in the room — the
    // exact situation after a network blip, which used to leave the roster
    // empty for the rest of the lesson.
    final teacher = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-ROSTER&role=teacher&key=$teacherKey'));
    final teacherInbox = StreamQueue<dynamic>(teacher.stream);
    addTearDown(() async {
      await teacherInbox.cancel();
      await teacher.sink.close();
    });
    await teacherInbox.next; // the greeting

    final replay = await teacherInbox.nextWhere(
      (frame) =>
          SyncProtocol.decode(frame)?.type == SyncEventType.participantJoined,
      const Duration(seconds: 3),
    );
    expect(SyncProtocol.decode(replay)!.participantName, 'Ana',
        reason: 'reconnecting must not erase the students already present');
  });

  test('a student who disconnects leaves the roster, for good', () async {
    await send('POST', '/api/session', {
      'id': 'CLASS-LEAVE',
      'teacherKey': 'LEAVEKEY',
    });

    final teacher = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-LEAVE&role=teacher&key=LEAVEKEY'));
    final teacherInbox = StreamQueue<dynamic>(teacher.stream);
    addTearDown(() async {
      await teacherInbox.cancel();
      await teacher.sink.close();
    });
    await teacherInbox.next; // the greeting

    final student = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-LEAVE&name=Ana&device=Android'));
    final studentInbox = StreamQueue<dynamic>(student.stream);
    await studentInbox.next; // the greeting
    final joined = await teacherInbox.nextWhere(
      (frame) =>
          SyncProtocol.decode(frame)?.type == SyncEventType.participantJoined,
      const Duration(seconds: 3),
    );
    final pid = SyncProtocol.decode(joined)!.participantId;

    // The connection dies (Wi-Fi blip, phone locked). The teacher must see
    // the leave, and the host must actually forget the student: an onError
    // path that only removed the socket used to keep them listed forever.
    await studentInbox.cancel();
    await student.sink.close();

    final left = await teacherInbox.nextWhere(
      (frame) => SyncProtocol.decode(frame)?.type == SyncEventType.participantLeft,
      const Duration(seconds: 3),
    );
    expect(SyncProtocol.decode(left)!.participantId, pid);

    // A fresh teacher socket proves the roster is really clean, not just
    // that a participant_left frame went out.
    final again = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-LEAVE&role=teacher&key=LEAVEKEY'));
    final againInbox = StreamQueue<dynamic>(again.stream);
    addTearDown(() async {
      await againInbox.cancel();
      await again.sink.close();
    });
    await againInbox.next; // the greeting
    await expectLater(
      againInbox.nextWhere(
        (frame) =>
            SyncProtocol.decode(frame)?.type == SyncEventType.participantJoined,
        const Duration(milliseconds: 600),
      ),
      throwsA(isA<TimeoutException>()),
      reason: 'a departed student must not be replayed to the reconnected '
          'teacher',
    );
  });

  test('ending a session stops serving, closes the room, and clears the file',
      () async {
    const teacherKey = 'ENDKEY';
    await send('POST', '/api/session',
        {'id': 'CLASS-END', 'teacherKey': teacherKey});
    final dir = Directory.systemTemp.createTempSync('end');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/final.pdf')..writeAsStringSync('%PDF-1.4');
    host.registerDocument('final.pdf', file.path);
    await send('POST', '/api/document', {
      'teacherKey': teacherKey,
      'documentName': 'final.pdf',
      'totalPages': 4,
    });

    final student = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-END&name=Ana&device=Android'));
    final studentInbox = StreamQueue<dynamic>(student.stream);
    addTearDown(() async {
      await studentInbox.cancel();
      await student.sink.close();
    });
    await studentInbox.next; // the greeting

    final snap = await json(await send('GET', '/api/session?id=CLASS-END'));
    final url = (snap['session'] as Map)['documentUrl'] as String;
    final target = Uri.parse(url);

    final ended = await send('POST', '/api/end', {'teacherKey': teacherKey});
    expect(ended.statusCode, 200);

    // The student is told the class is over.
    final bye = await studentInbox.nextWhere(
      (frame) => SyncProtocol.decode(frame)?.type == SyncEventType.sessionEnded,
      const Duration(seconds: 3),
    );
    expect(SyncProtocol.decode(bye), isNotNull);

    // The kept URL must stop working, and the room must refuse new sockets.
    final kept = await send('GET', '${target.path}?${target.query}');
    expect(kept.statusCode, 403);
    final refused = await send('GET', '/ws?session=CLASS-END&name=Ana');
    expect(refused.statusCode, 403);

    // The next session starts with a clean slate: no phantom document id.
    await send('POST', '/api/session',
        {'id': 'CLASS-END2', 'teacherKey': teacherKey});
    final next = await json(await send('GET', '/api/session?id=CLASS-END2'));
    expect((next['session'] as Map)['documentId'], isNull);
    expect((next['session'] as Map)['documentName'], isNull);
  });

  test('the student download path really moves the file, and the token gates '
      'it', () async {
    const teacherKey = 'DLKEY';
    await send('POST', '/api/session',
        {'id': 'CLASS-DL', 'teacherKey': teacherKey});
    final dir = Directory.systemTemp.createTempSync('dl');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/deck.pptx')..writeAsStringSync('PK-zip-bytes');
    host.registerDocument('deck.pptx', file.path);
    await send('POST', '/api/document', {
      'teacherKey': teacherKey,
      'documentName': 'deck.pptx',
      'totalPages': 12,
    });

    // Exactly what SyncProvider.downloadDocument() does: take the URL out of
    // the snapshot and fetch it over HTTP.
    final snap = await json(await send('GET', '/api/session?id=CLASS-DL'));
    final url = (snap['session'] as Map)['documentUrl'] as String;

    final bytes = await DocumentDownloader.fetch(url);
    expect(bytes, isNotNull, reason: 'the download button has to have bytes');
    expect(utf8.decode(bytes!), 'PK-zip-bytes');

    // Guessing the filename on the hotspot is not enough.
    final denied = await DocumentDownloader.fetch(
        'http://127.0.0.1:$port/files/deck.pptx');
    expect(denied, isNull);
  });

  // This route did not exist on this host, so "Sync all" and the per-student
  // "Take control" button both came back 404 — and a 404 is what flips the
  // app's status chip to a red "Not sharing", so the failure looked like the
  // whole classroom had gone rather than like one missing button.
  test('a teacher casting a video moves the whole class', () async {
    const teacherKey = 'VIDKEY';
    await send('POST', '/api/session',
        {'id': 'CLASS-VID', 'teacherKey': teacherKey});
    final dir = Directory.systemTemp.createTempSync('vid');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/lesson.mp4')
      ..writeAsStringSync('fake-mp4-bytes-for-the-test');
    host.registerDocument('lesson.mp4', file.path);
    await send('POST', '/api/document', {
      'teacherKey': teacherKey,
      'documentName': 'lesson.mp4',
    });

    final student = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-VID&name=Ana&device=Android'));
    final studentInbox = StreamQueue<dynamic>(student.stream);
    addTearDown(() async {
      await studentInbox.cancel();
      await student.sink.close();
    });
    await studentInbox.next; // the greeting

    // Without the teacher key, playback is not the student's to change.
    final refused = await send('POST', '/api/video',
        {'positionMs': 5000, 'playing': true});
    expect(refused.statusCode, 403);

    // What the teacher's player sends when it starts.
    final started = await json(await send('POST', '/api/video', {
      'teacherKey': teacherKey,
      'positionMs': 4200,
      'playing': true,
      'durationMs': 600000,
    }));
    expect((started['session'] as Map)['videoPlaying'], isTrue);
    expect((started['session'] as Map)['videoPositionMs'], 4200);

    // The student is told, not left guessing.
    final relayed = await studentInbox.nextWhere(
      (frame) =>
          SyncProtocol.decode(frame)?.type == SyncEventType.videoChanged,
      const Duration(seconds: 3),
    );
    final event = SyncProtocol.decode(relayed)!;
    expect(event.videoPositionMs, 4200,
        reason: 'the class has to land on the same moment');
    expect(event.videoPlaying, isTrue);

    // A seek is its own frame, so a teacher moving around a recording is not
    // fighting the previous position.
    await send('POST', '/api/video',
        {'teacherKey': teacherKey, 'positionMs': 90000, 'playing': false});
    final seeked = SyncProtocol.decode(await studentInbox.nextWhere(
      (frame) =>
          SyncProtocol.decode(frame)?.type == SyncEventType.videoChanged,
      const Duration(seconds: 3),
    ))!;
    expect(seeked.videoPositionMs, 90000);
    expect(seeked.videoPlaying, isFalse);

    // A position past the end is clamped rather than published: a phone would
    // sit at the end forever trying to reach a moment that does not exist.
    final clamped = await json(await send('POST', '/api/video', {
      'teacherKey': teacherKey,
      'positionMs': 99999999,
    }));
    expect((clamped['session'] as Map)['videoPositionMs'], 600000);
  });

  // A player cannot play from a file it has to read end to end, and seeking is
  // impossible without ranges. This is the difference between a video that
  // works and one that buffers to the end of the recording before starting.
  test('the shared video answers a range request with just those bytes',
      () async {
    const teacherKey = 'RANGEKEY';
    await send('POST', '/api/session',
        {'id': 'CLASS-RANGE', 'teacherKey': teacherKey});
    final dir = Directory.systemTemp.createTempSync('range');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bytes = '0123456789abcdefghij';
    final file = File('${dir.path}/clip.mp4')..writeAsStringSync(bytes);
    host.registerDocument('clip.mp4', file.path);
    final ok = await json(await send('POST', '/api/document',
        {'teacherKey': teacherKey, 'documentName': 'clip.mp4'}));
    final target = Uri.parse((ok['session'] as Map)['documentUrl'] as String);

    final client = HttpClient();
    final request = await client.openUrl(
        'GET', Uri.parse('http://127.0.0.1:$port${target.path}?${target.query}'));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=5-9');
    final response = await request.close();
    addTearDown(client.close);

    expect(response.statusCode, 206);
    expect(response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 5-9/${bytes.length}');
    expect(await response.transform(utf8.decoder).join(), '56789');
    expect(response.headers.value(HttpHeaders.contentTypeHeader),
        startsWith('video/mp4'));
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
  });

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

  // A phone that sleeps or slips off the hotspot never sends a FIN, so its
  // socket stays open while nobody is behind it and the onDone/onError paths
  // never fire. Without a presence sweep, the teacher's roster kept that
  // student for the rest of the lesson. These run with test-sized timeouts.
  test('a silent student loses their seat; a heartbeating one keeps it',
      () async {
    host.presenceTimeout = const Duration(milliseconds: 500);
    host.sweepInterval = const Duration(milliseconds: 100);
    addTearDown(() {
      host.presenceTimeout = const Duration(seconds: 30);
      host.sweepInterval = const Duration(seconds: 10);
    });

    await send('POST', '/api/session', {
      'id': 'CLASS-HB',
      'teacherKey': 'HBKEY',
    });

    final teacher = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-HB&role=teacher&key=HBKEY'));
    final teacherInbox = StreamQueue<dynamic>(teacher.stream);
    addTearDown(() async {
      await teacherInbox.cancel();
      await teacher.sink.close();
    });
    await teacherInbox.next; // the greeting

    final student = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-HB&name=Ana&device=Android'));
    final studentInbox = StreamQueue<dynamic>(student.stream);
    addTearDown(() async {
      await studentInbox.cancel();
      await student.sink.close();
    });
    await studentInbox.next; // the greeting

    final joined = await teacherInbox.nextWhere(
      (frame) =>
          SyncProtocol.decode(frame)?.type == SyncEventType.participantJoined,
      const Duration(seconds: 3),
    );
    final pid = SyncProtocol.decode(joined)!.participantId;

    // Exactly what the student client puts on the wire, on its timer.
    final beat = Timer.periodic(const Duration(milliseconds: 100), (_) {
      student.sink.add(SyncProtocol.encode(SyncEvent(
        type: SyncEventType.heartbeat,
        sessionId: 'CLASS-HB',
        participantName: 'Ana',
      )));
    });
    addTearDown(beat.cancel);

    // Well past the 500 ms timeout, with the sweep running every 100 ms.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await expectLater(
      teacherInbox.nextWhere(
        (frame) =>
            SyncProtocol.decode(frame)?.type == SyncEventType.participantLeft,
        const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
      reason: 'a heartbeating student must keep their seat',
    );

    // Stop saying "still here" and the host has to notice — otherwise the
    // check above passed because no sweep ever ran.
    beat.cancel();
    final left = await teacherInbox.nextWhere(
      (frame) =>
          SyncProtocol.decode(frame)?.type == SyncEventType.participantLeft,
      const Duration(seconds: 3),
    );
    expect(SyncProtocol.decode(left)!.participantId, pid);
  });

  test('the student client keeps its own seat warm, and lets it go on leave',
      () async {
    host.presenceTimeout = const Duration(milliseconds: 500);
    host.sweepInterval = const Duration(milliseconds: 100);
    addTearDown(() {
      host.presenceTimeout = const Duration(seconds: 30);
      host.sweepInterval = const Duration(seconds: 10);
    });

    await send('POST', '/api/session', {
      'id': 'CLASS-CLI',
      'teacherKey': 'CLIKEY',
    });

    final teacher = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-CLI&role=teacher&key=CLIKEY'));
    final teacherInbox = StreamQueue<dynamic>(teacher.stream);
    addTearDown(() async {
      await teacherInbox.cancel();
      await teacher.sink.close();
    });
    await teacherInbox.next; // the greeting

    // The real client, heartbeating on a test-sized timer.
    final client = ClasscastClient(
      heartbeatInterval: const Duration(milliseconds: 100),
    );
    addTearDown(client.dispose);
    client.subscribe(
      host: '127.0.0.1',
      port: port,
      sessionId: 'CLASS-CLI',
      name: 'Ana',
      device: 'Android',
    );

    await teacherInbox.nextWhere(
      (frame) =>
          SyncProtocol.decode(frame)?.type == SyncEventType.participantJoined,
      const Duration(seconds: 3),
    );

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await expectLater(
      teacherInbox.nextWhere(
        (frame) =>
            SyncProtocol.decode(frame)?.type == SyncEventType.participantLeft,
        const Duration(milliseconds: 300),
      ),
      throwsA(isA<TimeoutException>()),
      reason: 'the client has to keep its own seat warm',
    );

    // Leaving must stop the heartbeat too, or the roster would keep a ghost.
    await client.disconnect();
    final left = await teacherInbox.nextWhere(
      (frame) =>
          SyncProtocol.decode(frame)?.type == SyncEventType.participantLeft,
      const Duration(seconds: 3),
    );
    expect(SyncProtocol.decode(left), isNotNull);
  });

  test('a student finds the classroom even when the first address is wrong',
      () async {
    const teacherKey = 'FALLKEY';
    await send('POST', '/api/session',
        {'id': 'CLASS-FALL', 'teacherKey': teacherKey});
    final dir = Directory.systemTemp.createTempSync('fall');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/fall.pdf')..writeAsStringSync('%PDF fall');
    host.registerDocument('fall.pdf', file.path);
    await send('POST', '/api/document', {
      'teacherKey': teacherKey,
      'documentName': 'fall.pdf',
    });

    // What the joining code carries: this phone's hotspot address first, then
    // the Wi-Fi one. A student connected to the second cannot reach the first,
    // and the other way round, so probing only the first is a coin flip on
    // which setup the teacher happened to be using.
    final sync = SyncProvider();
    addTearDown(sync.dispose);
    final joined = await sync.join(
      rawInput: NetworkService.qrPayload(
        host: '10.255.255.1',
        port: port,
        sessionId: 'CLASS-FALL',
        altHosts: ['127.0.0.1'],
      ),
      studentName: 'Ana',
    );

    expect(joined, isTrue,
        reason: 'one unreachable address must not fail the whole join');
    expect(sync.host, '127.0.0.1',
        reason: 'the student keeps the address that answered');

    final bytes = await DocumentDownloader.fetch(sync.snapshot!.documentUrl!);
    expect(utf8.decode(bytes!), '%PDF fall');
  });

  // The host turns its advertised address into the URL every student
  // downloads from. A teacher who switches from the classroom Wi-Fi to a
  // hotspot gets a new address, and updating only the session left every
  // joined student holding a URL on an address that no longer existed: they
  // were on the teacher's roster and their download failed with no way to tell
  // why.
  test('a joined student is told when the classroom moves to a new address',
      () async {
    const teacherKey = 'ADDRKEY';
    await send('POST', '/api/session',
        {'id': 'CLASS-ADDR', 'teacherKey': teacherKey});
    final dir = Directory.systemTemp.createTempSync('addr');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/moved.pdf')
        ..writeAsStringSync('%PDF-1.4 moved');
    host.registerDocument('moved.pdf', file.path);
    await send('POST', '/api/document', {
      'teacherKey': teacherKey,
      'documentName': 'moved.pdf',
    });

    final student = IOWebSocketChannel.connect(Uri.parse(
        'ws://127.0.0.1:$port/ws?session=CLASS-ADDR&name=Ana&device=Android'));
    final studentInbox = StreamQueue<dynamic>(student.stream);
    addTearDown(() async {
      await studentInbox.cancel();
      await student.sink.close();
    });
    await studentInbox.next; // the greeting

    final before = await json(await send('GET', '/api/session?id=CLASS-ADDR'));
    expect((before['session'] as Map)['documentUrl'], contains('127.0.0.1'));

    // The hotspot comes on.
    host.setAdvertisedIp('192.168.43.1');

    final moved = await studentInbox.nextWhere(
      (frame) => (SyncProtocol.decode(frame)?.documentUrl ?? '')
          .contains('192.168.43.1'),
      const Duration(seconds: 3),
    );
    expect(SyncProtocol.decode(moved), isNotNull,
        reason: 'the student has to be handed the address that now serves them');

    final after = await json(await send('GET', '/api/session?id=CLASS-ADDR'));
    expect((after['session'] as Map)['hostIp'], '192.168.43.1');
  });

  test('re-announcing a session also restates the address, for a laptop host',
      () async {
    // The same fix on the REST route: the teacher app posts the address it is
    // advertising, so a host that learned its own at boot stops publishing a
    // stale one after the classroom moves networks.
    final reannounced = await json(await send('POST', '/api/session', {
      'id': 'CLASS-ADDR2',
      'teacherKey': 'ADDR2KEY',
      'advertisedIp': '192.168.5.2',
    }));
    expect((reannounced['session'] as Map)['hostIp'], '192.168.5.2');

    // Anything that is not an address is refused rather than published in a
    // URL a student has to fetch.
    final junk = await json(await send('POST', '/api/session', {
      'id': 'CLASS-ADDR2',
      'teacherKey': 'ADDR2KEY',
      'advertisedIp': 'evil.example.com/../x',
    }));
    expect((junk['session'] as Map)['hostIp'], '192.168.5.2');

    // And without the key the address is not theirs to change.
    final noKey = await send('POST', '/api/session', {
      'id': 'CLASS-ADDR2',
      'advertisedIp': '10.0.0.9',
    });
    expect(noKey.statusCode, 403);
  });

  test('a student downloads from the address that answered, not the one '
      'advertised', () async {
    // The teacher is on the school Wi-Fi and serving a hotspot: the host
    // advertises its hotspot address, and this student is on the Wi-Fi one.
    // The URL in the snapshot named the address the host advertised, which
    // this phone may not be able to open at all.
    host.setAdvertisedIp('192.168.43.1');
    const teacherKey = 'URLKEY';
    await send('POST', '/api/session',
        {'id': 'CLASS-URL', 'teacherKey': teacherKey});
    final dir = Directory.systemTemp.createTempSync('url');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/mixed.pdf')..writeAsStringSync('%PDF mixed');
    host.registerDocument('mixed.pdf', file.path);
    await send('POST', '/api/document', {
      'teacherKey': teacherKey,
      'documentName': 'mixed.pdf',
    });

    final sync = SyncProvider();
    addTearDown(sync.dispose);
    final joined = await sync.join(
      rawInput: 'classcast://join?host=127.0.0.1&port=$port&session=CLASS-URL',
      studentName: 'Ana',
    );

    expect(joined, isTrue, reason: 'the student joined the classroom');
    final url = sync.snapshot!.documentUrl!;
    expect(url, startsWith('http://127.0.0.1:$port/'),
        reason: 'the file has to come from the address that answered, not '
            'from one this phone cannot reach');
    expect(url, contains('mixed.pdf'));

    // And it is not just a well-formed string: the bytes really move.
    final bytes = await DocumentDownloader.fetch(url);
    expect(bytes, isNotNull);
    expect(utf8.decode(bytes!), '%PDF mixed');
  });

  test('a student joins on the second address in the code, and the file still '
      'comes', () async {
    // The teacher is casting over *someone else's* hotspot: their phone is a
    // client on a network somebody else owns, holding 192.168.43.123 rather
    // than a gateway address. Every student on that hotspot can reach it, and
    // so can the teacher — but a student standing somewhere else cannot, which
    // is why the code carries more than one address and the phone keeps the one
    // that answers.
    const teacherKey = 'ALTKEY';
    await send('POST', '/api/session',
        {'id': 'CLASS-ALT', 'teacherKey': teacherKey});
    host.setAdvertisedIp('192.168.43.123');
    final dir = Directory.systemTemp.createTempSync('alt');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/alt.pdf')..writeAsStringSync('%PDF alt');
    host.registerDocument('alt.pdf', file.path);
    await send('POST', '/api/document', {
      'teacherKey': teacherKey,
      'documentName': 'alt.pdf',
    });

    final sync = SyncProvider();
    addTearDown(sync.dispose);

    // Exactly the code the teacher's phone shows: its own address on that
    // network, plus the others it has.
    final joined = await sync.join(
      rawInput: NetworkService.qrPayload(
        host: '192.168.43.123',
        port: port,
        sessionId: 'CLASS-ALT',
        altHosts: ['127.0.0.1'],
      ),
      studentName: 'Ana',
    );

    expect(joined, isTrue,
        reason: 'one unreachable address must not fail the whole join');
    expect(sync.host, '127.0.0.1',
        reason: 'the student keeps the address that answered');
    expect(sync.snapshot!.documentUrl, startsWith('http://127.0.0.1:$port/'),
        reason: 'and the document comes from that same address');

    final bytes = await DocumentDownloader.fetch(sync.snapshot!.documentUrl!);
    expect(bytes, isNotNull);
    expect(utf8.decode(bytes!), '%PDF alt');
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
