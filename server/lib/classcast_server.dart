import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      _teacherKey =
          key ?? DateTime.now().millisecondsSinceEpoch.toString();
      _session = {
        'id': body['id'] ?? 'CLASS-${_code()}',
        'name': body['name'] ?? 'Classroom',
        'subject': body['subject'] ?? '',
        'allowAnonymous': body['allowAnonymous'] ?? true,
        'allowDownload': body['allowDownload'] ?? false,
        'allowStudentNav': body['allowStudentNav'] ?? false,
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      };
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
      _documentId = body['documentId'] as String? ?? '';
      _documentName = body['documentName'] as String? ?? '';
      _totalPages = (body['totalPages'] as num?)?.toInt() ?? 0;
      _page = 1;
      _broadcast(_snapshotEvent('document_changed'));
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

    final staticFiles = createStaticHandler(
      filesDir,
      listDirectories: false,
    );

    // File download (only when the session allows it).
    Handler files = (Request req) async {
      if (_session?['allowDownload'] != true) {
        // Metadata (converted PDF preview) is still served to viewers
        // through the app channel; raw download needs permission.
        return Response.forbidden('Downloads are disabled by the teacher');
      }
      return staticFiles(req);
    };

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
          if (req.url.path.startsWith('files/')) {
            final sub = req.url.path.substring('files/'.length);
            return files(Request(
              req.method,
              req.requestedUri.replace(path: '/$sub'),
              headers: req.headers,
              body: req.read(),
            ));
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
      return webSocketHandler(
        (WebSocketChannel channel, String? _) =>
            _onConnect(channel, params),
      )(req);
    };
  }

  void _onConnect(
      WebSocketChannel channel, Map<String, String> params) {
    final sessionId = params['session'] ?? '';
    final name = params['name'] ?? 'Student';
    final device = params['device'] ?? '';
    _sockets.add(channel);
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
        'page': _page,
        'totalPages': _totalPages,
        'syncPaused': _syncPaused,
      };

  Map<String, dynamic> _snapshotEvent(String type) => {
        'type': type,
        'sessionId': _session?['id'] ?? '',
        'documentId': _documentId.isEmpty ? null : _documentId,
        'documentName': _documentName.isEmpty ? null : _documentName,
        'page': _page,
        'totalPages': _totalPages,
      };

  bool _checkTeacher(Map<String, dynamic> body) {
    if (_session == null) return false;
    return body['teacherKey'] == _teacherKey;
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
    final server =
        await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    // Resolve the real LAN address students must use (not 0.0.0.0).
    try {
      final ifaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      for (final nic in ifaces) {
        for (final addr in nic.addresses) {
          if (!addr.isLoopback) {
            advertisedIp = addr.address;
            break;
          }
        }
        if (advertisedIp.isNotEmpty) break;
      }
    } catch (_) {/* keep empty */}
    return server;
  }
}
