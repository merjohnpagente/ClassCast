import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Authoritative classroom state on the teacher host.
///
/// 64 KB is far above any real control frame and far below anything that
/// could hurt the machine.
const int kMaxBodyBytes = 64 * 1024;

/// Ceiling on a file the server will read into memory to derive a page count.
const int kMaxDerivedBytes = 64 * 1024 * 1024;

/// Stops pulling once [limit] bytes have been seen, so a body of any size
/// cannot be buffered whole.
Stream<List<int>> _cappedBytes(Stream<List<int>> source, int limit) async* {
  var seen = 0;
  await for (final chunk in source) {
    seen += chunk.length;
    if (seen > limit) return;
    yield chunk;
  }
}

/// Single-session prototype (multi-session is a Phase-4 extension).
/// All teacher controls require [teacherKey]; students can only
/// join + read + receive broadcasts.
class ClasscastServer {
  final int port;
  final String filesDir;
  final String? webDir;

  // --- session state (authoritative) ---
  Map<String, dynamic>? _session;
  String _teacherKey = '';
  String _documentId = '';
  String _documentName = '';

  /// Unguessable part of the download URL, regenerated for every share.
  String _documentToken = '';
  int _page = 1;
  int _totalPages = 0;
  bool _syncPaused = false;
  final Map<String, Map<String, dynamic>> _participants = {};

  final Set<WebSocketChannel> _sockets = {};

  /// Participant id → its socket, so "take control" can be aimed at one student
  /// instead of every one of them. Without it the per-student button on the
  /// Students screen could only ever pull the whole room back.
  final Map<String, WebSocketChannel> _socketsById = {};

  /// Real LAN address students use (resolved in [serve]).
  String advertisedIp = '';

  ClasscastServer({
    required this.port,
    required this.filesDir,
    this.webDir,
  });

  Handler get handler {
    final router = Router();

    router.get('/api/ping', (Request req) {
      return Response.ok(jsonEncode({'ok': true, 'app': 'classcast'}),
          headers: {'content-type': 'application/json'});
    });

    router.get('/api/session', (Request req) {
      final id = req.url.queryParameters['id'] ?? '';
      if (_session == null || _session!['id'] != id) {
        return _json(404, {'ok': false, 'error': 'Session unavailable'});
      }
      return _json(200, {'ok': true, 'session': _snapshot()});
    });

    router.post('/api/session', (Request req) async {
      // Teacher creates/starts a session from the laptop host UI
      // or from the Flutter teacher app (same LAN).
      final body = await _readJson(req);
      final key = body['teacherKey'] as String?;
      if (_session != null && key != _teacherKey) {
        return _json(403, {'ok': false, 'error': 'Permission denied'});
      }
      if (_session == null && (key == null || key.isEmpty)) {
        // An empty key would make `_checkTeacher` pass for everyone.
        _teacherKey = _code();
      } else {
        _teacherKey = key!.isEmpty ? _code() : key;
      }
      // Update in place: re-posting must not wipe the session the teacher is
      // already presenting (or reset createdAt / flags back to defaults).
      _session ??= {
        'id': body['id'] ?? 'CLASS-${_code()}',
        'name': body['name'] ?? 'Classroom',
        'subject': '',
        'allowAnonymous': true,
        'allowDownload': false,
        'allowStudentNav': false,
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      };
      final s = _session!;
      s['name'] = body['name'] ?? s['name'];
      s['subject'] = body['subject'] ?? s['subject'];
      s['allowAnonymous'] = body['allowAnonymous'] ?? s['allowAnonymous'];
      s['allowDownload'] = body['allowDownload'] ?? s['allowDownload'];
      s['allowStudentNav'] =
          body['allowStudentNav'] ?? s['allowStudentNav'];
      s['isActive'] = true;
      _broadcast(_snapshotEvent('session_state'));
      return _json(200, {
        'ok': true,
        'session': _snapshot(),
        'teacherKey': _teacherKey,
      });
    });

    router.post('/api/page', (Request req) async {
      final body = await _readJson(req);
      if (!_checkTeacher(body)) {
        return _json(403, {'ok': false, 'error': 'Permission denied'});
      }
      // The teacher app only learns a deck's real slide count after opening
      // it, so it may publish the total alongside the page.
      final declaredTotal = (body['totalPages'] as num?)?.toInt() ?? 0;
      if (declaredTotal > 0) _totalPages = declaredTotal;
      final page = (body['page'] as num?)?.toInt() ?? _page;
      _page = _totalPages > 0 ? page.clamp(1, _totalPages) : page;
      _broadcast(_snapshotEvent('page_changed'));
      return _json(200, {'ok': true, 'session': _snapshot()});
    });

    router.post('/api/document', (Request req) async {
      final body = await _readJson(req);
      if (!_checkTeacher(body)) {
        return _json(403, {'ok': false, 'error': 'Permission denied'});
      }
      // Unshare: teacher cleared the document from the library.
      if (body['clear'] == true) {
        _documentId = '';
        _documentName = '';
        _documentToken = '';
        _totalPages = 0;
        _page = 1;
        _broadcast(_snapshotEvent('document_changed'));
        return _json(200, {'ok': true, 'session': _snapshot()});
      }
      final name = body['documentName'] as String? ?? '';
      if (name.isEmpty) {
        return _json(400, {'ok': false, 'error': 'documentName is required'});
      }
      // Refuse to announce a document the host cannot actually serve, so the
      // teacher sees the error instead of every student getting a blank page.
      if (!_isServable(name)) {
        return _json(404, {
          'ok': false,
          'error': 'File "$name" is not in the shared directory',
          'filesDir': filesDir,
        });
      }
      _documentId = body['documentId'] as String? ?? '';
      _documentName = name;
      _documentToken = _code();
      final declared = (body['totalPages'] as num?)?.toInt() ?? 0;
      // The teacher app does not know a freshly picked file's page count
      // yet, so derive it here rather than showing students "Page 3" with no
      // total. This is a heuristic; an unknown count degrades to 0.
      _totalPages = declared > 0 ? declared : _derivedPageCount(name);
      _page = 1;
      _broadcast(_snapshotEvent('document_changed'));
      return _json(200, {'ok': true, 'session': _snapshot()});
    });

    router.post('/api/pause', (Request req) async {
      final body = await _readJson(req);
      if (!_checkTeacher(body)) {
        return _json(403, {'ok': false, 'error': 'Permission denied'});
      }
      // Reuses the full-snapshot event so clients can mirror it without a
      // new wire type.
      _syncPaused = body['paused'] as bool? ?? !_syncPaused;
      _broadcast(_snapshotEvent('session_state'));
      return _json(200, {'ok': true, 'session': _snapshot()});
    });

    // Pull one wandering student — or the whole room — back onto the class
    // page. This route did not exist, so the teacher client's request fell
    // through to the catch-all and came back 404: "Sync all" and the
    // per-student "Take control" button did nothing at all against this host,
    // and the 404 then flipped the app's status chip to a red "Not sharing".
    router.post('/api/take-control', (Request req) async {
      final body = await _readJson(req);
      if (!_checkTeacher(body)) {
        return _json(403, {'ok': false, 'error': 'Permission denied'});
      }
      final pid = body['participantId'] as String? ?? '';
      final frame = jsonEncode({
        'type': 'take_control',
        'sessionId': _session?['id'] ?? '',
        if (pid.isNotEmpty) 'participantId': pid,
        'page': _page,
        'totalPages': _totalPages,
      });
      var notified = 0;
      if (pid.isEmpty) {
        for (final socket in _socketsById.values) {
          try {
            socket.sink.add(frame);
            notified++;
          } catch (_) {/* that student just left */}
        }
      } else {
        final socket = _socketsById[pid];
        if (socket != null) {
          try {
            socket.sink.add(frame);
            notified = 1;
          } catch (_) {/* that student just left */}
        }
      }
      return _json(200, {'ok': true, 'notified': notified});
    });

    router.post('/api/end', (Request req) async {
      final body = await _readJson(req);
      if (!_checkTeacher(body)) {
        return _json(403, {'ok': false, 'error': 'Permission denied'});
      }
      _broadcast({
        'type': 'session_ended',
        'sessionId': _session?['id'] ?? '',
      });
      _session = null;
      // Ending the session must end the sharing too. The socket is still
      // listening, so a student who kept the URL could otherwise keep pulling
      // the document long after the teacher ended the class.
      _documentName = '';
      _documentToken = '';
      return _json(200, {'ok': true});
    });

    router.get('/ws', wsRoute());

    // Document delivery. Viewing the document that is currently on screen is
    // the core feature, so it is always allowed; `allowDownload` only gates
    // the *rest* of the shared folder. (Note: anything a student can render,
    // they can also save — this is a classroom courtesy switch, not DRM.)
    Future<Response> serveFile(String requestedName, String? presented) async {
      // The session must be running and the request must carry the token the
      // snapshot handed out, so typing the filename on the classroom Wi-Fi is
      // not enough to read what the teacher is showing.
      final token = _documentToken;
      if (_session == null || token.isEmpty) {
        return Response.forbidden('No session is running');
      }
      if (presented != token) {
        return Response.forbidden('Not allowed');
      }
      final raw = Uri.decodeComponent(requestedName);
      if (!_isSafeRelativeName(raw)) return Response.notFound('not found');
      final root = p.normalize(filesDir);
      final target = p.normalize(p.join(root, raw));
      if (!p.isWithin(root, target)) return Response.notFound('not found');
      int length;
      try {
        final file = File(target);
        if (!file.existsSync()) return Response.notFound('not found');
        length = file.lengthSync();
        final isCurrent = raw == _documentName;
        if (!isCurrent && _session?['allowDownload'] != true) {
          return Response.forbidden('Downloads are disabled by the teacher');
        }
        return Response.ok(
          file.openRead(),
          headers: {
            'content-type':
                lookupMimeType(file.path) ?? 'application/octet-stream',
            'content-disposition': isCurrent ? 'inline' : 'attachment',
            'content-length': length.toString(),
            // The shared document changes as the teacher moves on.
            'cache-control': 'no-store',
          },
        );
      } catch (_) {
        return Response.notFound('not found');
      }
    }

    final cascade = Cascade();
    if (webDir != null) {
      final web = createStaticHandler(
        webDir!,
        defaultDocument: 'index.html',
      );
      cascade.add(web);
    }
    // shelf's Cascade treats 404/405 as "unacceptable" by default and moves on
    // to the next handler, which silently broke this API: 404 is also how we
    // report "no such session" and "that file is not in the shared directory",
    // and those JSON bodies carry the message the teacher app displays. Every
    // one of them was being replaced with a bare "not found". Cascade only on
    // a *genuinely* unmatched route (no JSON content type), so real API 404s
    // reach the client intact.
    bool shouldCascade(Response res) =>
        (res.statusCode == 404 || res.statusCode == 405) &&
        !(res.headers['content-type']?.contains('application/json') ?? false);

    // Only add the web static handler when a web build was configured:
    // Cascade.handler throws "no inner handlers" if the inner cascade is
    // empty, which broke every request when the server ran without --web
    // (the default laptop API-only mode).
    final outer = Cascade(shouldCascade: shouldCascade)
        .add(router.call)
        .add((req) {
          const prefix = 'files/';
          if (req.url.path.startsWith(prefix)) {
            return serveFile(req.url.path.substring(prefix.length),
                req.url.queryParameters['t']);
          }
          return Response.notFound('not found');
        });
    if (webDir != null) outer.add(cascade.handler);
    return outer.handler;
  }

  /// WebSocket endpoint. Query: ?session=<id>&name=<student>&device=<...>.
  /// Handled by shelf_web_socket (proper HTTP-upgrade hijack).
  Handler wsRoute() {
    return (Request req) {
      final params = req.url.queryParameters;
      final sessionId = params['session'] ?? '';
      // Validate BEFORE the HTTP upgrade: a wrong or ended session must never
      // receive a snapshot or show up in the participant list.
      if (_session == null) {
        return Response.forbidden('No session is running');
      }
      if (sessionId.isEmpty || sessionId != _session!['id']) {
        return Response.forbidden('Unknown session');
      }
      // `?role=teacher` is a claim; without the key it is not a subscription to
      // the whole roster.
      final claimsTeacher = params['role'] == 'teacher';
      final isTeacher =
          claimsTeacher && _teacherKey.isNotEmpty && params['key'] == _teacherKey;
      if (claimsTeacher && !isTeacher) {
        return Response.forbidden('Teacher key required');
      }
      return webSocketHandler(
        (WebSocketChannel channel, String? _) =>
            _onConnect(channel, params, isTeacher: isTeacher),
      )(req);
    };
  }

  void _onConnect(
    WebSocketChannel channel,
    Map<String, String> params, {
    bool isTeacher = false,
  }) {
    final sessionId = params['session'] ?? '';
    final name = params['name'] ?? 'Student';
    final device = params['device'] ?? '';
    _sockets.add(channel);
    // The teacher subscribes too (so it learns who joined), but must never
    // appear in its own student roster.
    if (isTeacher) {
      channel.sink.add(jsonEncode(_snapshotEvent('session_state')));
      channel.stream.listen(
        (_) {/* teacher control happens over the REST API, not frames */},
        onDone: () => _sockets.remove(channel),
        onError: (_) => _sockets.remove(channel),
        cancelOnError: false,
      );
      return;
    }
    final pid =
        'ws-${_sockets.length}-${DateTime.now().microsecondsSinceEpoch}';
    _participants[pid] = {'id': pid, 'name': name, 'device': device};
    _socketsById[pid] = channel;
    // Reconnecting students get the current state immediately.
    channel.sink.add(jsonEncode(_snapshotEvent('session_state')));
    _broadcast({
      'type': 'participant_joined',
      'sessionId': sessionId,
      'participantId': pid,
      'participantName': name,
    });
    channel.stream.listen(
      (frame) => _onFrame(channel, pid, sessionId, frame),
      onDone: () {
        _sockets.remove(channel);
        _socketsById.remove(pid);
        _participants.remove(pid);
        _broadcast({
          'type': 'participant_left',
          'sessionId': sessionId,
          'participantId': pid,
        });
      },
      onError: (_) {
        _sockets.remove(channel);
        _socketsById.remove(pid);
      },
      cancelOnError: false,
    );
  }


  void _onFrame(WebSocketChannel channel, String pid, String sessionId,
      Object? frame) {
    Map<String, dynamic>? msg;
    try {
      msg = Map<String, dynamic>.from(jsonDecode(frame as String) as Map);
    } catch (_) {
      return;
    }
    // Students must not control the presentation: the class page is teacher
    // control only, over REST with the teacher key. They may, however, *ask*
    // for attention and report where they are, and those have to reach the
    // teacher's screen — a hand raised that the teacher never sees is a broken
    // feature, and it was exactly that: this handler only knew `join`, so every
    // other frame a student sent fell on the floor.
    final name = msg['participantName'] as String? ?? 'Student';
    switch (msg['type']) {
      case 'join':
        _participants[pid] = {
          'id': pid,
          'name': name,
          'device': msg['message'] ?? ''
        };
        _socketsById[pid] = channel;
        channel.sink.add(jsonEncode(_snapshotEvent('session_state')));
        _broadcast({
          'type': 'participant_joined',
          'sessionId': sessionId,
          'participantId': pid,
          'participantName': name,
        });
        return;
      case 'hand_raised':
        _broadcastParticipant('hand_raised', sessionId, pid, name,
            page: null);
        return;
      case 'hand_lowered':
        _broadcastParticipant('hand_lowered', sessionId, pid, name,
            page: null);
        return;
      case 'student_page_changed':
        final page = (msg['page'] as num?)?.toInt();
        if (page == null) return;
        // Reported, not applied: the teacher sees where this student is.
        _broadcastParticipant('student_page_changed', sessionId, pid, name,
            page: page);
        return;
      default:
        return;
    }
  }

  /// Relays one student's own event to everybody, including the teacher.
  ///
  /// The name is taken from the roster rather than the frame, so a student
  /// cannot rename themselves in the teacher's list by lying in a message.
  void _broadcastParticipant(
    String type,
    String sessionId,
    String pid,
    String fallbackName, {
    int? page,
  }) {
    if (pid.isEmpty) return;
    _broadcast({
      'type': type,
      'sessionId': sessionId,
      'participantId': pid,
      'participantName': _participants[pid]?['name'] ?? fallbackName,
      if (page != null) 'page': page,
      'totalPages': _totalPages,
    });
  }

  Map<String, dynamic> _snapshot() => {
        if (_session != null) ..._session!,
        'hostIp': advertisedIp,
        'port': port,
        'documentId': _documentId.isEmpty ? null : _documentId,
        'documentName': _documentName.isEmpty ? null : _documentName,
        // Students cannot render a local path; they fetch these bytes from
        // the teacher host. Without this the viewer has nothing to load.
        'documentUrl': _documentUrl(),
        'page': _page,
        'totalPages': _totalPages,
        'syncPaused': _syncPaused,
      };

  Map<String, dynamic> _snapshotEvent(String type) => {
        'type': type,
        'sessionId': _session?['id'] ?? '',
        'documentId': _documentId.isEmpty ? null : _documentId,
        'documentName': _documentName.isEmpty ? null : _documentName,
        'documentUrl': _documentUrl(),
        'page': _page,
        'totalPages': _totalPages,
        'syncPaused': _syncPaused,
      };

  /// Absolute URL of the shared document, or null when none is shared.
  /// Falls back to a root-relative path before the LAN address is resolved
  /// so a same-origin web viewer still resolves it.
  String? _documentUrl() {
    if (_documentName.isEmpty) return null;
    final encoded = Uri.encodeComponent(_documentName);
    final suffix = _documentToken.isEmpty ? '' : '?t=$_documentToken';
    if (advertisedIp.isEmpty) return '/files/$encoded$suffix';
    return 'http://$advertisedIp:$port/files/$encoded$suffix';
  }

  bool _checkTeacher(Map<String, dynamic> body) {
    if (_session == null) return false;
    if (_teacherKey.isEmpty) return false;
    return body['teacherKey'] == _teacherKey;
  }

  /// Rejects empty names, absolute paths, and any `..` segment.
  bool _isSafeRelativeName(String name) {
    if (name.isEmpty || name.contains('\u0000')) return false;
    if (p.isAbsolute(name)) return false;
    return !name
        .split(RegExp(r'[/\\]'))
        .any((seg) => seg.isEmpty || seg == '.' || seg == '..');
  }

  /// True when [name] is a real file inside the shared directory.
  bool _isServable(String name) {
    if (!_isSafeRelativeName(name)) return false;
    try {
      final root = p.normalize(filesDir);
      final target = p.normalize(p.join(root, name));
      if (!p.isWithin(root, target)) return false;
      return File(target).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Page count for a shared file, derived from the bytes the server already
  /// has. PDFs are counted from page objects, PowerPoint decks from the slide
  /// parts inside the zip; anything else degrades to 0 ("unknown total").
  int _derivedPageCount(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return _pdfPageCount(name);
    if (lower.endsWith('.pptx')) return _pptxSlideCount(name);
    return 0;
  }

  /// Page count for a PDF, derived by counting page objects.
  ///
  /// The teacher app cannot report this for a file it just picked, and the
  /// server already holds the bytes. Counting `/Type /Page` (excluding
  /// `/Type /Pages`) is a well-known heuristic: it is right for ordinary
  /// exported decks and returns 0 for compressed/linearised edge cases,
  /// which the UI already treats as "unknown total".
  int _pdfPageCount(String name) {
    if (!name.toLowerCase().endsWith('.pdf')) return 0;
    final bytes = _readShared(name);
    if (bytes == null) return 0;
    // Cap the read: a huge deck should not stall the share action.
    const maxScan = 32 * 1024 * 1024;
    if (bytes.length > maxScan) return 0;
    final text = latin1.decode(bytes, allowInvalid: true);
    final pattern = RegExp(r'/Type\s*/Page(?![s])');
    return pattern.allMatches(text).length;
  }

  /// Slide count for a .pptx, read from the zip central directory.
  ///
  /// Only the directory is parsed — the slide parts themselves are never
  /// inflated — so this stays cheap even for a deck full of photos.
  int _pptxSlideCount(String name) {
    final bytes = _readShared(name);
    if (bytes == null) return 0;
    try {
      return _zipEntryNames(bytes)
          .where((entry) =>
              entry.startsWith('ppt/slides/slide') && entry.endsWith('.xml'))
          .length;
    } catch (_) {
      return 0;
    }
  }

  /// Names of the entries in a zip archive, from its central directory.
  List<String> _zipEntryNames(List<int> data) {
    final view = Uint8List.fromList(data);
    // End of central directory record: signature PK\x05\x06.
    var eocd = -1;
    for (var i = view.length - 22; i >= 0 && i >= view.length - 22 - 65536; i--) {
      if (view[i] == 0x50 &&
          view[i + 1] == 0x4b &&
          view[i + 2] == 0x05 &&
          view[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) return const [];
    final count = view[eocd + 10] | (view[eocd + 11] << 8);
    final offset =
        (view[eocd + 16] | (view[eocd + 17] << 8) | (view[eocd + 18] << 16) |
                (view[eocd + 19] << 24))
            .toUnsigned(32);
    if (offset < 0 || offset >= view.length) return const [];

    final names = <String>[];
    var cursor = offset;
    for (var i = 0; i < count; i++) {
      // Central directory file header: PK\x01\x02.
      if (cursor + 46 > view.length) break;
      if (view[cursor] != 0x50 ||
          view[cursor + 1] != 0x4b ||
          view[cursor + 2] != 0x01 ||
          view[cursor + 3] != 0x02) {
        break;
      }
      final nameLength = view[cursor + 28] | (view[cursor + 29] << 8);
      final extraLength = view[cursor + 30] | (view[cursor + 31] << 8);
      final commentLength = view[cursor + 32] | (view[cursor + 33] << 8);
      final nameStart = cursor + 46;
      if (nameStart + nameLength > view.length) break;
      names.add(latin1.decode(
        view.sublist(nameStart, nameStart + nameLength),
        allowInvalid: true,
      ));
      cursor = nameStart + nameLength + extraLength + commentLength;
    }
    return names;
  }

  /// Reads a file from the shared folder, or null when it is missing or unsafe.
  Uint8List? _readShared(String name) {
    if (!_isSafeRelativeName(name)) return null;
    try {
      final root = p.normalize(filesDir);
      final target = p.normalize(p.join(root, name));
      if (!p.isWithin(root, target)) return null;
      final file = File(target);
      if (!file.existsSync()) return null;
      // The PDF path is capped; this one was not, and it is read synchronously
      // inside an async handler, so one huge deck blocked the whole server.
      if (file.lengthSync() > kMaxDerivedBytes) return null;
      return file.readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  void _broadcast(Map<String, dynamic> event) {
    final frame = jsonEncode(event);
    for (final s in _sockets.toList()) {
      try {
        s.sink.add(frame);
      } catch (_) {
        _sockets.remove(s);
      }
    }
  }

  Future<Map<String, dynamic>> _readJson(Request req) async {
    try {
      // Control frames are a handful of short strings. Reading without a cap
      // let anything on the classroom network make this machine buffer an
      // arbitrarily large body.
      final bytes = await _cappedBytes(req.read(), kMaxBodyBytes)
          .fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final text = utf8.decode(bytes, allowMalformed: true);
      if (text.isEmpty) return {};
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } catch (_) {
      return {};
    }
  }

  Response _json(int status, Map<String, dynamic> body) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Six characters sliced out of the clock were guessable from the time a
  /// session started; this is the one credential on every control endpoint.
  String _code() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(8, (i) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<HttpServer> serve() async {
    // Resolve first so the very first snapshot already carries a usable
    // documentUrl instead of a root-relative placeholder.
    advertisedIp = await _resolveLanIp();
    return shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  }

  /// Pick the address students can actually reach.
  ///
  /// Taking the first non-loopback IPv4 is wrong on a typical dev machine:
  /// VMware / VirtualBox / Hyper-V / Docker / WSL adapters usually win and
  /// hand students an address that routes nowhere.
  static Future<String> _resolveLanIp() async {
    const virtualHints = <String>[
      'loopback',
      'vmware',
      'virtualbox',
      'vethernet',
      'hyper-v',
      'docker',
      'wsl',
      'tailscale',
      'zerotier',
      'bluetooth',
      'vpn',
      'pseudo',
    ];
    String? fallback;
    try {
      final ifaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      for (final nic in ifaces) {
        for (final addr in nic.addresses) {
          if (addr.isLoopback) continue;
          final ip = addr.address;
          fallback ??= ip;
          final name = nic.name.toLowerCase();
          if (!virtualHints.any(name.contains)) return ip;
        }
      }
    } catch (_) {
      // Enumeration is best-effort; fall through to whatever we found.
    }
    return fallback ?? '';
  }
}
