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
    final url = (ok['session'] as Map)['documentUrl'] as String;
    expect(url, contains('lesson.pptx'));

    // A joined student gets this URL from the snapshot, token included.
    final target = Uri.parse(url);
    final file = await send(
        'GET', '${target.path}?${target.query}');
    expect(file.statusCode, 200);
    expect(await file.transform(utf8.decoder).join(), 'PK-not-really-a-zip');

    // Guessing the filename on the classroom Wi-Fi is not enough: the token is
    // what makes the URL safe to hand out, so it is required.
    final guessed = await send('GET', '/files/lesson.pptx');
    expect(guessed.statusCode, 403);

    // Anything else on the phone stays private. Dart's client normalises the
    // .. segments away before the request is even sent, so this never reaches
    // the file handler — and the server's own path checks cover the rest.
    final other = await send('GET', '/files/../../etc/passwd');
    expect(other.statusCode, 404);

    dir.deleteSync(recursive: true);
  });

  test('a filename with a literal % is served, and readable cross-origin',
      () async {
    await send('POST', '/api/session', {'id': 'CLASS-PCT', 'teacherKey': 'k8'});
    final dir = Directory.systemTemp.createTempSync('hostpct');
    final doc = File('${dir.path}/100%.pdf')..writeAsStringSync('%PDF-1.4 pct');

    host.registerDocument('100%.pdf', doc.path);
    final ok = await json(await send('POST', '/api/document',
        {'teacherKey': 'k8', 'documentName': '100%.pdf'}));
    final target = Uri.parse((ok['session'] as Map)['documentUrl'] as String);
    final res = await send('GET', '${target.path}?${target.query}');

    // The URL percent-encodes the name; the host must decode exactly once, or
    // an ordinary document comes back a 404.
    expect(res.statusCode, 200);
    expect(await res.transform(utf8.decoder).join(), '%PDF-1.4 pct');
    // A student running the web build lives on a different origin; without
    // this the browser refuses to hand the bytes to the app.
    expect(res.headers.value('access-control-allow-origin'), '*');

    dir.deleteSync(recursive: true);
  });

  test('unsharing stops serving the file, even to a kept URL', () async {
    await send('POST', '/api/session', {'id': 'CLASS-U', 'teacherKey': 'k7'});
    final dir = Directory.systemTemp.createTempSync('hostdoc');
    final doc = File('${dir.path}/kept.pdf')..writeAsStringSync('%PDF-1.4');

    host.registerDocument('kept.pdf', doc.path);
    final ok = await json(await send('POST', '/api/document',
        {'teacherKey': 'k7', 'documentName': 'kept.pdf'}));
    final target = Uri.parse((ok['session'] as Map)['documentUrl'] as String);
    expect((await send('GET', '${target.path}?${target.query}')).statusCode,
        200);

    host.clearDocument();
    expect(
        (await send('GET', '${target.path}?${target.query}')).statusCode, 403);

    dir.deleteSync(recursive: true);
  });

  test('the teacher socket needs the key, so role=teacher is not a shortcut',
      () async {
    await send('POST', '/api/session',
        {'id': 'CLASS-K', 'teacherKey': 'k5'});
    final withoutKey = await send('GET', '/ws?session=CLASS-K&role=teacher');
    expect(withoutKey.statusCode, 403);
  });

  test('a websocket is refused before the upgrade for a wrong session',
      () async {
    await send('POST', '/api/session', {'id': 'CLASS-WS', 'teacherKey': 'k3'});
    final res = await send('GET', '/ws?session=CLASS-NOPE');
    expect(res.statusCode, 403);
  });

  test('take control needs the teacher key', () async {
    await send('POST', '/api/session', {'id': 'CLASS-TC', 'teacherKey': 'k9'});
    final denied = await send('POST', '/api/take-control', {'teacherKey': 'wrong'});
    expect(denied.statusCode, 403);
    final allowed = await json(
        await send('POST', '/api/take-control', {'teacherKey': 'k9'}));
    expect(allowed['ok'], isTrue);
  });

  test('stopping releases the port', () async {
    await ClasscastHost.instance.stop();
    final again = await ClasscastHost.instance.start(port: port);
    expect(again, isTrue, reason: 'the port must be free after stop');
    await ClasscastHost.instance.stop();
  });
}
