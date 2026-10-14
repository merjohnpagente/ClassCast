import 'dart:convert';
import 'dart:io';

import 'package:classcast_offline/services/host/classcast_host.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ClasscastHost host;
  late int port;

  setUp(() async {
    host = ClasscastHost.instance;
    final ok = await host.start(port: 0, advertisedIp: '127.0.0.1');
    expect(ok, isTrue, reason: 'the host must be able to bind a port');
    port = host.port;
    expect(port, greaterThan(0));
  });

  tearDown(() => host.stop());

  Future<HttpClientResponse> send(String method, String path,
      [Map<String, dynamic>? body]) async {
    final client = HttpClient();
    final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    request.headers.contentType = ContentType.json;
    if (body != null) request.write(jsonEncode(body));
    return request.close();
  }

  Future<Map<String, dynamic>> json(HttpClientResponse r) async =>
      Map<String, dynamic>.from(jsonDecode(await r.transform(utf8.decoder).join()) as Map);

  test('pings so students can probe it', () async {
    final res = await send('GET', '/api/ping');
    expect(res.statusCode, 200);
    expect((await json(res))['app'], 'classcast');
  });

  test('a session can be created, read and paged through', () async {
    final created = await json(await send('POST', '/api/session', {
      'id': 'CLASS-TEST',
      'name': 'Physics',
      'teacherKey': 'k1',
    }));
    expect(created['ok'], isTrue);
    expect(created['teacherKey'], 'k1');

    final snap = await json(await send('GET', '/api/session?id=CLASS-TEST'));
    expect((snap['session'] as Map)['name'], 'Physics');

    // Control without the teacher key is refused.
    final refused = await send('POST', '/api/page', {'page': 2});
    expect(refused.statusCode, 403);

    final paged = await json(
        await send('POST', '/api/page', {'teacherKey': 'k1', 'page': 2, 'totalPages': 5}));
    final session = paged['session'] as Map;
    expect(session['page'], 2);
    expect(session['totalPages'], 5);

    // Unknown session id is a JSON 404, never a fake "connected".
    final missing = await send('GET', '/api/session?id=NOPE');
    expect(missing.statusCode, 404);
    expect((await json(missing))['ok'], isFalse);
  });

  test('only the shared document is served, and only from the teacher key',
      () async {
    await send('POST', '/api/session', {'id': 'CLASS-T', 'teacherKey': 'k2'});
    final dir = Directory.systemTemp.createTempSync('hostdoc');
    final doc = File('${dir.path}/lesson.pptx')
      ..writeAsStringSync('PK-not-really-a-zip');

    // Nothing registered yet: the host must refuse to announce it.
    final refused = await send('POST', '/api/document',
        {'teacherKey': 'k2', 'documentName': 'lesson.pptx'});
    expect(refused.statusCode, 404);

    host.registerDocument('lesson.pptx', doc.path);
    final ok = await json(await send('POST', '/api/document',
        {'teacherKey': 'k2', 'documentName': 'lesson.pptx', 'totalPages': 3}));
    expect(ok['ok'], isTrue);
    expect((ok['session'] as Map)['documentUrl'], contains('lesson.pptx'));

    final file = await send('GET', '/files/lesson.pptx');
    expect(file.statusCode, 200);
    expect(await file.transform(utf8.decoder).join(), 'PK-not-really-a-zip');

    // Anything else on the phone stays private.
    final other = await send('GET', '/files/../../etc/passwd');
    expect(other.statusCode, 404);

    dir.deleteSync(recursive: true);
  });

  test('a websocket is refused before the upgrade for a wrong session',
      () async {
    await send('POST', '/api/session', {'id': 'CLASS-WS', 'teacherKey': 'k3'});
    final res = await send('GET', '/ws?session=CLASS-NOPE');
    expect(res.statusCode, 403);
  });

  test('stopping releases the port', () async {
    await ClasscastHost.instance.stop();
    final again = await ClasscastHost.instance.start(port: port);
    expect(again, isTrue, reason: 'the port must be free after stop');
    await ClasscastHost.instance.stop();
  });
}
