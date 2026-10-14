import 'dart:convert';
import 'dart:io';

import 'package:classcast_server/classcast_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

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
    return server.handler(Request(
      method,
      Uri.parse(path),
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

  void writeFile(String name, String contents) {
    File('${tmp.path}${Platform.pathSeparator}$name')
        .writeAsStringSync(contents);
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
      final [id, key] = await startSession();
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
      await call('POST', '/api/document',
          jsonEncode({'teacherKey': key, 'documentName': 'lesson.pdf'}));

      final res = await call('GET', '/files/lesson.pdf');
      expect(res.statusCode, 200);
      expect(res.headers['content-disposition'], 'inline');
    });

    test('other files still require download permission', () async {
      final [id, key] = await startSession(allowDownload: false);
      writeFile('answerkey.pdf', '%PDF-1.4');
      final res = await call('GET', '/files/answerkey.pdf');
      expect(res.statusCode, 403);
    });

    test('download permission unlocks the rest of the folder', () async {
      final [id, key] = await startSession(allowDownload: true);
      writeFile('answerkey.pdf', '%PDF-1.4');
      final res = await call('GET', '/files/answerkey.pdf');
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
  });

  group('file safety', () {
    test('traversal outside the shared folder is blocked', () async {
      await startSession(allowDownload: true);
      for (final attempt in [
        '/files/..%2F..%2Fsecret.txt',
        '/files/../secret.txt',
        '/files/subdir/../../secret.txt',
      ]) {
        final res = await call('GET', attempt);
        expect(res.statusCode, 404, reason: 'must block $attempt');
      }
    });

    test('a missing file is 404, not a crash', () async {
      await startSession(allowDownload: true);
      expect((await call('GET', '/files/nothing.pdf')).statusCode, 404);
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
}