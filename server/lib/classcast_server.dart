import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  int _page = 1;
  int _totalPages = 0;
  bool _syncPaused = false;
  final Map<String, Map<String, dynamic>> _participants = {};

  final Set<WebSocketChannel> _sockets = {};

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
      final declared = (body['totalPages'] as num?)?.toInt() ?? 0;
      // The teacher app does not know a freshly picked file's page count
      // yet, so derive it here rather than showing students "Page 3" with no
      // total. This is a heuristic; an unknown count degrades to 0.
      _totalPages = declared > 0 ? declared : _pdfPageCount(name);
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
      return _json(200, {'ok': true});
    });

    router.get('/ws', wsRoute());

    // Document delivery. Viewing the document that is currently on screen is
    // the core feature, so it is always allowed; `allowDownload` only gates
    // the *rest* of the shared folder. (Note: anything a student can render,
    // they can also save — this is a classroom courtesy switch, not DRM.)
    Future<Response> serveFile(String requestedName) async {
      final raw = Uri.decodeComponent(requestedName);
      if (!_isSafeRelativeName(raw)) return Response.notFound('not found');
      final root = p.normalize(filesDir);
      final target = File(p.normalize(p.join(root, raw)));
      if (!p.isWithin(root, target)) return Response.notFound('not found');
      File file;
      int length;
      try {
        file = target;
        if (!file.existsSync()) return Response.notFound('not found');
        length = file.lengthSync();
      } catch (_) {
        return Response.notFound('not found');
      }
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
    }

    final cascade = Cascade();
    if (webDir != null) {
      final web = createStaticHandler(
        webDir!,
        defaultDocument: 'index.html',
      );
      cascade.add(web);
    }
    return Cascade()
        .add(router.call)
        .add((req) {
          const prefix = 'files/';
          if (req.url.path.startsWith(prefix)) {
            return serveFile(req.url.path.substring(prefix.length));
          }
          return Response.notFound('not found');
        })
        .add(cascade.handler)
        .handler;
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
      return webSocketHandler(
        (WebSocketChannel channel, String? _) =>
            _onConnect(channel, params, isTeacher: params['role'] == 'teacher'),
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
        'ws-${_sockets.length}-${DateTime.now().millisecondsSinceEpoch}';
    _participants[pid] = {'id': pid, 'name': name, 'device': device};
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
        _participants.remove(pid);
        _broadcast({
          'type': 'participant_left',
          'sessionId': sessionId,
          'participantId': pid,
        });
      },
      onError: (_) => _sockets.remove(channel),
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
    // Students must not control the presentation: only `join` frames
    // from non-teacher sockets are accepted. Teacher control frames
    // arrive via the REST API above (validated by teacherKey).
    if (msg['type'] == 'join') {
      final name = msg['participantName'] as String? ?? 'Student';
      _participants[pid] = {
        'id': pid,
        'name': name,
        'device': msg['message'] ?? ''
      };
      channel.sink.add(jsonEncode(_snapshotEvent('session_state')));
      _broadcast({
        'type': 'participant_joined',
        'sessionId': sessionId,
        'participantId': pid,
        'participantName': name,
      });
    }
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
    if (advertisedIp.isEmpty) return '/files/$encoded';
    return 'http://$advertisedIp:$port/files/$encoded';
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
      final f = File(p.normalize(p.join(filesDir, name)));
      if (!p.isWithin(p.normalize(filesDir), f)) return false;
      return f.existsSync();
    } catch (_) {
      return false;
    }
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
    try {
      final root = p.normalize(filesDir);
      final f = File(p.normalize(p.join(root, name)));
      if (!p.isWithin(root, f) || !f.existsSync()) return 0;
      // Cap the read: a huge deck should not stall the share action.
      const maxScan = 32 * 1024 * 1024;
      final len = f.lengthSync();
      if (len <= 0 || len > maxScan) return 0;
      final text = latin1.decode(f.readAsBytesSync(), allowInvalid: true);
      final pattern = RegExp(r'/Type\s*/Page(?![s])');
      return pattern.allMatches(text).length;
    } catch (_) {
      return 0;
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
      final text = await req.readAsString();
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

  String _code() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = DateTime.now().millisecondsSinceEpoch;
    return List.generate(
        6, (i) => chars[(rnd >> (i * 3)) % chars.length]).join();
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
    List<Interface> ifaces;
    try {
      ifaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
    } catch (_) {
      return '';
    }
    String? fallback;
    for (final nic in ifaces) {
      for (final addr in nic.addresses) {
        if (addr.isLoopback) continue;
        final ip = addr.address;
        if (fallback == null) fallback = ip;
        final name = nic.name.toLowerCase();
        if (!virtualHints.any(name.contains)) return ip;
      }
    }
    return fallback ?? '';
  }
}
