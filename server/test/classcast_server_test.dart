import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:classcast_server/classcast_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

/// Black-box tests for the classroom host.
///
/// Everything is driven through [ClasscastServer.handler], so no ports are
/// bound and no network is touched. These cover the guarantees the Flutter
/// clients depend on: teacher-key enforcement, the document URL students
/// fetch, view-vs-download separation, traversal safety and session
/// lifecycle.
void main() {
  late Directory tmp;
  late ClasscastServer server;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('classcast_test');
    server = ClasscastServer(port: 0, filesDir: tmp.path);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<Response> call(
    String method,
    String path, [
    Object? body,
  ]) async {
    // Shelf requires an absolute requestedUri; everything here is same-host.
    final uri = Uri.parse('http://localhost:8080$path');
    return server.handler(Request(
      method,
      uri,
      body: body,
      headers: const {'content-type': 'application/json'},
    ));
  }

  Future<Map<String, dynamic>> body(Response r) async =>
      Map<String, dynamic>.from(
          jsonDecode(await r.readAsString()) as Map);

  /// Creates a session and returns `[sessionId, teacherKey]`.
  Future<List<String>> startSession({
    String name = 'Physics',
    bool allowDownload = false,
  }) async {
    final res = await body(await call('POST', '/api/session', jsonEncode({
      'name': name,
      'allowDownload': allowDownload,
    })));
    final key = res['teacherKey'] as String;
    final id = (res['session'] as Map)['id'] as String;
    return [id, key];
  }

  /// Shares a file and returns the "path?query" a joined student would use.
  /// The token in it is what makes the URL safe to hand out.
  Future<String> shareAndUrl(String key, String name) async {
    final res = await body(await call('POST', '/api/document',
        jsonEncode({'teacherKey': key, 'documentName': name})));
    final url = Uri.parse((res['session'] as Map)['documentUrl'] as String);
    return '${url.path}${url.query.isEmpty ? '' : '?${url.query}'}';
  }

  void writeFile(String name, String contents) {
    File('${tmp.path}${Platform.pathSeparator}$name')
        .writeAsStringSync(contents);
  }

  void writeFileBytes(String name, List<int> bytes) {
    File('${tmp.path}${Platform.pathSeparator}$name').writeAsBytesSync(bytes);
  }

  /// Minimal zip whose entries look like a PowerPoint deck. The host only
  /// reads the central directory, never the part contents, so the payloads can
  /// stay empty.
  List<int> _fakePptx({required int slides}) {
    final entries = <String>[
      '[Content_Types].xml',
      'ppt/presentation.xml',
      for (var i = 1; i <= slides; i++) 'ppt/slides/slide$i.xml',
      'ppt/slides/_rels/slide1.xml.rels',
      'ppt/media/image1.png',
    ];

    void u16(List<int> out, int value) {
      out.add(value & 0xFF);
      out.add((value >> 8) & 0xFF);
    }

    void u32(List<int> out, int value) {
      for (var i = 0; i < 4; i++) {
        out.add((value >> (i * 8)) & 0xFF);
      }
    }

    final out = <int>[];
    final central = <int>[];
    for (final name in entries) {
      final nameBytes = ascii.encode(name);
      final offset = out.length;

      // Local file header.
      out.addAll([0x50, 0x4B, 0x03, 0x04]);
      u16(out, 20); // version needed
      u16(out, 0); // flags
      u16(out, 0); // method: stored
      u16(out, 0); // time
      u16(out, 0); // date
      u32(out, 0); // crc
      u32(out, 0); // compressed size
      u32(out, 0); // uncompressed size
      u16(out, nameBytes.length);
      u16(out, 0);
      out.addAll(nameBytes);

      // Central directory file header.
      central.addAll([0x50, 0x4B, 0x01, 0x02]);
      u16(central, 20); // version made by
      u16(central, 20); // version needed
      u16(central, 0); // flags
      u16(central, 0); // method
      u16(central, 0); // time
      u16(central, 0); // date
      u32(central, 0); // crc
      u32(central, 0); // compressed size
      u32(central, 0); // uncompressed size
      u16(central, nameBytes.length);
      u16(central, 0); // extra
      u16(central, 0); // comment
      u16(central, 0); // disk number
      u16(central, 0); // internal attributes
      u32(central, 0); // external attributes
      u32(central, offset);
      central.addAll(nameBytes);
    }

    final centralStart = out.length;
    out.addAll(central);
    out.addAll([0x50, 0x4B, 0x05, 0x06]);
    u16(out, 0); // this disk
    u16(out, 0); // disk with the directory
    u16(out, entries.length);
    u16(out, entries.length);
    u32(out, central.length);
    u32(out, centralStart);
    u16(out, 0); // comment length
    return out;
  }

  group('session lifecycle', () {
    test('creates a session and returns a snapshot', () async {
      final [id, key] = await startSession();
      expect(id, isNotEmpty);
      expect(key, isNotEmpty);

      final snap = await body(await call('GET', '/api/session?id=$id'));
      expect(snap['ok'], isTrue);
      expect((snap['session'] as Map)['name'], 'Physics');
    });

    test('unknown session id is 404, never a fake Connected state', () async {
      final res = await call('GET', '/api/session?id=CLASS-NOPE');
      expect(res.statusCode, 404);
      final decoded = await body(res);
      expect(decoded['ok'], isFalse);
    });

    test('unknown session id is JSON with ok:false', () async {
      // The 404 path must stay machine-readable: the student's join flow
      // parses this body to decide between "wrong ID" and "host down".
      await startSession();
      final res = await call('GET', '/api/session?id=CLASS-NOPE');
      expect(res.headers['content-type'], contains('application/json'));
      final decoded = await body(res);
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], isNotNull);
    });

    test('no session running is 404', () async {
      final res = await call('GET', '/api/session?id=anything');
      expect(res.statusCode, 404);
    });

    test('ending the session makes it unavailable', () async {
      final [id, key] = await startSession();
      expect((await call('POST', '/api/end', jsonEncode({'teacherKey': key})))
          .statusCode, 200);
      expect((await call('GET', '/api/session?id=$id')).statusCode, 404);
    });

    test('ending a session unshares the file and leaves no phantom state',
        () async {
      final [_, key] = await startSession();
      writeFile('lesson.pdf', '%PDF-1.4');
      final url = await shareAndUrl(key, 'lesson.pdf');

      await call('POST', '/api/end', jsonEncode({'teacherKey': key}));

      // A student who kept the URL must not still be able to pull the file
      // after the class is over.
      expect((await call('GET', url)).statusCode, 403);

      // And the next session starts clean: a documentId that survived the end
      // used to resurface in the first snapshot, drawing a nameless file.
      final [id2, _] = await startSession(name: 'Next');
      final snap = await body(await call('GET', '/api/session?id=$id2'));
      final s = snap['session'] as Map;
      expect(s['documentId'], isNull);
      expect(s['documentName'], isNull);
      expect(s['totalPages'], 0);
      expect(s['page'], 1);
      expect(s['syncPaused'], isFalse);
    });

    test('re-posting updates in place instead of recreating', () async {
      final [id, key] = await startSession();
      final first = await body(await call(
          'GET', '/api/session?id=$id', null));
      final createdAt = (first['session'] as Map)['createdAt'];

      await call('POST', '/api/session', jsonEncode({
        'teacherKey': key,
        'name': 'Renamed',
        'subject': 'Physics',
      }));

      final second = await body(await call('GET', '/api/session?id=$id'));
      final s = second['session'] as Map;
      expect(s['createdAt'], createdAt, reason: 'createdAt must not reset');
      expect(s['name'], 'Renamed');
    });
  });

  group('teacher key enforcement', () {
    test('page control without a key is refused', () async {
      await startSession();
      expect(
        (await call('POST', '/api/page', jsonEncode({'page': 2}))).statusCode,
        403,
      );
    });

    test('a wrong key is refused', () async {
      await startSession();
      final res = await call('POST', '/api/page',
          jsonEncode({'teacherKey': 'not-the-key', 'page': 2}));
      expect(res.statusCode, 403);
    });

    test('an empty teacher key is replaced and never accepted', () async {
      final res = await body(await call(
          'POST', '/api/session', jsonEncode({'name': 'X', 'teacherKey': ''})));
      final issued = res['teacherKey'] as String;
      expect(issued, isNotEmpty, reason: 'server must not honour an empty key');

      expect(
        (await call('POST',
                '/api/page', jsonEncode({'teacherKey': '', 'page': 2})))
            .statusCode,
        403,
      );
    });

    test('the correct key is accepted', () async {
      final [id, key] = await startSession();
      final res = await call('POST', '/api/page',
          jsonEncode({'teacherKey': key, 'page': 3}));
      expect(res.statusCode, 200);
      expect(((await body(res))['session'] as Map)['page'], 3);
    });

    test('page is clamped to the document total', () async {
      final [id, key] = await startSession();
      writeFile('lesson.pdf', '%PDF-1.4 /Type /Page /Type /Pages /Type /Page');
      await call('POST', '/api/document', jsonEncode({
        'teacherKey': key,
        'documentName': 'lesson.pdf',
        'totalPages': 4,
      }));
      final res = await call('POST', '/api/page',
          jsonEncode({'teacherKey': key, 'page': 99}));
      expect(((await body(res))['session'] as Map)['page'], 4);
    });
  });

  group('document sharing', () {
    test('a file the host does not have is refused', () async {
      final [id, key] = await startSession();
      final res = await call('POST', '/api/document', jsonEncode({
        'teacherKey': key,
        'documentName': 'ghost.pdf',
      }));
      expect(res.statusCode, 404);
    });

    test('sharing publishes a documentUrl students can fetch', () async {
      final [id, key] = await startSession();
      writeFile('lesson.pdf', '%PDF-1.4 /Type /Page');
      final res = await body(await call('POST', '/api/document', jsonEncode({
        'teacherKey': key,
        'documentName': 'lesson.pdf',
      })));
      expect(res['ok'], isTrue);
      final s = res['session'] as Map;
      // The whole point of the fix: without this the student viewer has
      // nothing to load and renders "no longer on this device".
      expect(s['documentUrl'], isNotNull);
      expect(s['documentUrl'] as String, contains('lesson.pdf'));
    });

    test('page count is derived when the teacher does not know it', () async {
      final [id, key] = await startSession();
      // Two page objects plus one Pages node, which must not be counted.
      writeFile('lesson.pdf', '%PDF /Type /Page /Type /Pages /Type /Page');
      final res = await body(await call('POST', '/api/document', jsonEncode({
        'teacherKey': key,
        'documentName': 'lesson.pdf',
      })));
      expect((res['session'] as Map)['totalPages'], 2);
    });

    test('the current document is viewable even when downloads are off',
        () async {
      final [id, key] = await startSession(allowDownload: false);
      writeFile('lesson.pdf', '%PDF-1.4');
      final url = await shareAndUrl(key, 'lesson.pdf');

      final res = await call('GET', url);
      expect(res.statusCode, 200);
      expect(res.headers['content-disposition'], 'inline');

      // Guessing the filename on the classroom network is not enough.
      final guessed = await call('GET', '/files/lesson.pdf');
      expect(guessed.statusCode, 403);
      expect(res.statusCode, 200);
      expect(res.headers['content-disposition'], 'inline');
    });

    test('other files still require download permission', () async {
      final [id, key] = await startSession(allowDownload: false);
      writeFile('lesson.pdf', '%PDF-1.4');
      writeFile('answerkey.pdf', '%PDF-1.4');
      // Share the lesson, then ask for a different file with that token.
      final url = await shareAndUrl(key, 'lesson.pdf');
      final query = url.substring(url.indexOf('?'));
      final res = await call('GET', '/files/answerkey.pdf$query');
      expect(res.statusCode, 403);
    });

    test('download permission unlocks the rest of the folder', () async {
      final [id, key] = await startSession(allowDownload: true);
      writeFile('lesson.pdf', '%PDF-1.4');
      writeFile('answerkey.pdf', '%PDF-1.4');
      final url = await shareAndUrl(key, 'lesson.pdf');
      final query = url.substring(url.indexOf('?'));
      final res = await call('GET', '/files/answerkey.pdf$query');
      expect(res.statusCode, 200);
      expect(res.headers['content-disposition'], 'attachment');
    });

    test('clear unshares the document', () async {
      final [id, key] = await startSession();
      writeFile('lesson.pdf', '%PDF-1.4');
      await call('POST', '/api/document',
          jsonEncode({'teacherKey': key, 'documentName': 'lesson.pdf'}));

      final res = await body(await call(
          'POST', '/api/document', jsonEncode({'teacherKey': key, 'clear': true})));
      expect(res['ok'], isTrue);
      expect((res['session'] as Map)['documentUrl'], isNull);
      expect((res['session'] as Map)['documentId'], isNull);
    });

    test('slide count is derived for a .pptx deck', () async {
      final [id, key] = await startSession();
      // A real deck's slides live in the zip; the host reads their names from
      // the central directory, so students get "Page 2 of 3" instead of an
      // unknown total.
      writeFileBytes('deck.pptx', _fakePptx(slides: 3));
      final res = await body(await call('POST', '/api/document',
          jsonEncode({'teacherKey': key, 'documentName': 'deck.pptx'})));
      expect((res['session'] as Map)['totalPages'], 3);
    });

    test('a file the teacher app could not count accepts a published total',
        () async {
      final [id, key] = await startSession();
      writeFileBytes('deck.pptx', _fakePptx(slides: 3));
      await call('POST', '/api/document', jsonEncode({
        'teacherKey': key,
        'documentName': 'deck.pptx',
        'totalPages': 0,
      }));
      // The teacher app publishes the real count once it has opened the file.
      final res = await body(await call('POST', '/api/page',
          jsonEncode({'teacherKey': key, 'page': 2, 'totalPages': 3})));
      final session = res['session'] as Map;
      expect(session['totalPages'], 3);
      expect(session['page'], 2);
    });
  });

  group('file safety', () {
    test('traversal outside the shared folder is blocked', () async {
      final [id, key] = await startSession(allowDownload: true);
      writeFile('lesson.pdf', '%PDF-1.4');
      final url = await shareAndUrl(key, 'lesson.pdf');
      final query = url.substring(url.indexOf('?'));
      for (final attempt in [
        '/files/..%2F..%2Fsecret.txt',
        '/files/../secret.txt',
        '/files/subdir/../../secret.txt',
      ]) {
        final res = await call('GET', '$attempt$query');
        expect(res.statusCode, 404, reason: 'must block $attempt');
      }
    });

    test('a missing file is 404, not a crash', () async {
      final [id, key] = await startSession(allowDownload: true);
      writeFile('lesson.pdf', '%PDF-1.4');
      final url = await shareAndUrl(key, 'lesson.pdf');
      final query = url.substring(url.indexOf('?'));
      expect((await call('GET', '/files/nothing.pdf$query')).statusCode, 404);
    });
  });

  group('pause', () {
    test('pause is reflected in the snapshot', () async {
      final [id, key] = await startSession();
      final res = await body(await call(
          'POST', '/api/pause', jsonEncode({'teacherKey': key, 'paused': true})));
      expect((res['session'] as Map)['syncPaused'], isTrue);

      final back = await body(await call(
          'POST', '/api/pause', jsonEncode({'teacherKey': key, 'paused': false})));
      expect((back['session'] as Map)['syncPaused'], isFalse);
    });

    test('pause without a teacher key is refused', () async {
      await startSession();
      expect((await call('POST', '/api/pause', jsonEncode({'paused': true})))
              .statusCode,
          403);
    });
  });

  group('websocket gate', () {
    test('a socket for an unknown session is rejected before the upgrade',
        () async {
      await startSession();
      final res = await call('GET', '/ws?session=CLASS-NOPE');
      expect(res.statusCode, 403);
      expect(await res.readAsString(), isNot(contains('page_changed')));
    });

    test('a socket with no session running is rejected', () async {
      final res = await call('GET', '/ws?session=CLASS-NOPE');
      expect(res.statusCode, 403);
    });
  });

  // Presence needs real sockets: a WebSocket upgrade only exists on a real
  // connection, and the case under test is exactly a socket that stays open
  // while the student behind it has gone (phone slept, hotspot dropped them).
  // So this group binds loopback and runs with short timeouts.
  group('presence heartbeat', () {
    late ClasscastServer live;
    late HttpServer http;
    late String sessionId;
    late String teacherKey;

    Future<Map<String, dynamic>> api(
      String method,
      String path, [
      Object? body,
    ]) async {
      final res = await live.handler(Request(
        method,
        Uri.parse('http://localhost:8080$path'),
        body: body,
        headers: const {'content-type': 'application/json'},
      ));
      return Map<String, dynamic>.from(
          jsonDecode(await res.readAsString()) as Map);
    }

    setUp(() async {
      live = ClasscastServer(
        port: 0,
        filesDir: tmp.path,
        presenceTimeout: const Duration(milliseconds: 500),
        sweepInterval: const Duration(milliseconds: 100),
      );
      http = await live.serve();
      final created = await api('POST', '/api/session',
          jsonEncode({'name': 'Physics'}));
      teacherKey = created['teacherKey'] as String;
      sessionId = (created['session'] as Map)['id'] as String;
    });

    tearDown(() async {
      await http.close(force: true);
    });

    /// Polls the collected frames for one matching [test], up to [limit].
    /// Frames arrive on a stream; the sweep is time-based, so this waits.
    Future<Map<String, dynamic>?> waitFor(
      List<Map<String, dynamic>> log,
      bool Function(Map<String, dynamic>) test,
      Duration limit,
    ) async {
      final deadline = DateTime.now().add(limit);
      while (DateTime.now().isBefore(deadline)) {
        for (final frame in log) {
          if (test(frame)) return frame;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return null;
    }

    IOWebSocketChannel connect(String query, List<Map<String, dynamic>> log) {
      final channel = IOWebSocketChannel.connect(
          Uri.parse('ws://127.0.0.1:${http.port}/ws?$query'));
      channel.stream.listen((frame) {
        final decoded = jsonDecode(frame as String);
        if (decoded is Map) {
          log.add(Map<String, dynamic>.from(decoded));
        }
      });
      addTearDown(() => channel.sink.close());
      return channel;
    }

    test('a student who goes silent is dropped from the roster', () async {
      final log = <Map<String, dynamic>>[];
      connect('session=$sessionId&role=teacher&key=$teacherKey', log);
      final student = connect('session=$sessionId&name=Ana', log);
      student.sink.add(jsonEncode({
        'type': 'join',
        'sessionId': sessionId,
        'participantName': 'Ana',
      }));

      final joined = await waitFor(
          log, (m) => m['type'] == 'participant_joined',
          const Duration(seconds: 3));
      expect(joined, isNotNull,
          reason: 'the student has to be on the roster first');
      final pid = joined!['participantId'];

      // No heartbeats: the socket stays open, the student does not.
      final left = await waitFor(
          log, (m) => m['type'] == 'participant_left',
          const Duration(seconds: 3));
      expect(left, isNotNull,
          reason: 'a silent seat must be swept off the roster');
      expect(left!['participantId'], pid);

      // And the host really forgot them: take control has nobody to reach.
      final ctrl = await api('POST', '/api/take-control',
          jsonEncode({'teacherKey': teacherKey, 'participantId': pid}));
      expect(ctrl['notified'], 0);
    });

    test('heartbeats keep a seat that silence would lose', () async {
      final log = <Map<String, dynamic>>[];
      connect('session=$sessionId&role=teacher&key=$teacherKey', log);
      final student = connect('session=$sessionId&name=Ana', log);
      student.sink.add(jsonEncode({
        'type': 'join',
        'sessionId': sessionId,
        'participantName': 'Ana',
      }));
      await waitFor(log, (m) => m['type'] == 'participant_joined',
          const Duration(seconds: 3));

      final beat = Timer.periodic(const Duration(milliseconds: 100), (_) {
        student.sink.add(jsonEncode({
          'type': 'heartbeat',
          'sessionId': sessionId,
          'participantName': 'Ana',
        }));
      });
      addTearDown(beat.cancel);

      // Well past the 500 ms timeout, with the sweep running every 100 ms.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(log.any((m) => m['type'] == 'participant_left'), isFalse,
          reason: 'a heartbeating student must keep their seat');

      // Stop saying "still here" and the sweeper has to notice — otherwise
      // the test above passed because no sweep ever ran.
      beat.cancel();
      final left = await waitFor(
          log, (m) => m['type'] == 'participant_left',
          const Duration(seconds: 3));
      expect(left, isNotNull,
          reason: 'the sweeper must still be watching after heartbeats stop');
    });

    test('the teacher socket is never swept', () async {
      final log = <Map<String, dynamic>>[];
      connect('session=$sessionId&role=teacher&key=$teacherKey', log);

      // The teacher never heartbeats; only students do. Past the timeout the
      // socket must still be alive, proven by a page change reaching it.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await api('POST', '/api/page',
          jsonEncode({'teacherKey': teacherKey, 'page': 2, 'totalPages': 5}));
      final relayed = await waitFor(
          log, (m) => m['type'] == 'page_changed',
          const Duration(seconds: 3));
      expect(relayed, isNotNull,
          reason: 'the teacher socket must never be swept');
    });
  });
}