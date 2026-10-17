import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The classroom host, running inside the teacher's phone.
///
/// This is the piece that makes the hotspot flow work at all: without a server
/// on the teacher's device, a session is just a row in a database and no
/// student can ever reach it. It speaks the same protocol as the laptop host in
/// `server/`, so both clients work unchanged.
///
/// Only the current document is served, straight from the path the teacher
/// picked — files are never copied around, and nothing else on the phone is
/// reachable.
class ClasscastHost {
  ClasscastHost._();

  static final ClasscastHost instance = ClasscastHost._();

  HttpServer? _server;
  int _port = 0;
  String _advertisedIp = '';

  // --- authoritative session state ---
  Map<String, dynamic>? _session;
  String _teacherKey = '';
  String _documentId = '';
  String _documentName = '';
  String _documentPath = '';

  /// Unguessable part of the download URL, regenerated for every share.
  String _fileToken = '';
  int _page = 1;
  int _totalPages = 0;
  bool _syncPaused = false;
  final Map<String, Map<String, dynamic>> _participants = {};

  /// How long a student may stay silent before the roster drops them.
  ///
  /// A phone that slept or slipped off the hotspot never sends a FIN, so its
  /// socket can look open while nobody is behind it. Students send a heartbeat
  /// every 10 seconds, so three misses is a departure. Tests shorten these.
  Duration presenceTimeout = const Duration(seconds: 30);
  Duration sweepInterval = const Duration(seconds: 10);

  /// Checks [_participants] for silent students. Runs only while somebody is
  /// in the room.
  Timer? _presenceTimer;

  /// Students with a raised hand, so a fresh teacher connection still sees it.
  final Set<WebSocketChannel> _sockets = {};

  /// Why the last [start] failed, in a sentence the teacher can act on.
  String? _lastStartError;
  String? get lastStartError => _lastStartError;

  /// Socket per student id. The roster is a broadcast, but pulling one student
  /// back to the class page has to reach exactly that student and nobody else.
  final Map<String, WebSocketChannel> _socketsById = {};

  /// Turns a bind failure into the one sentence that fits it. Everything else
  /// falls back to the port message, which really is the most common cause.
  static String _describeBindError(Object error) {
    final text = error.toString();
    if (text.contains('Failed to create socket')) {
      return 'The device refused to open a network socket. Turn off any VPN or '
          'private-DNS app and try again.';
    }
    if (text.contains('Permission denied')) {
      return 'ClassCast was not allowed to use the network. Grant the network '
          'permission for ClassCast, then try again.';
    }
    if (text.contains('No address') || text.contains('unavailable')) {
      return 'This device has no usable network. Connect to Wi-Fi or turn on '
          'the hotspot, then start the session again.';
    }
    return '';
  }

  bool get running => _server != null;
  int get port => _port;

  /// Address students should use. Falls back to the interface list so a session
  /// is still reachable when the caller could not resolve an IP.
  String get advertisedIp => _advertisedIp;

  String get joinUrl =>
      _advertisedIp.isEmpty ? '' : 'http://$_advertisedIp:$_port';

  /// Starts the host. Returns false when the port is taken or unavailable — the
  /// caller keeps showing the honest "students cannot reach you" state.
  ///
  /// [advertisedIp] is applied even when already running: switching from Wi-Fi
  /// to a hotspot mid-lesson left students with an address that no longer
  /// existed, with nothing to indicate why they stopped loading.
  Future<bool> start({
    required int port,
    String advertisedIp = '',
  }) async {
    if (advertisedIp.isNotEmpty) _advertisedIp = advertisedIp;
    if (running) return true;
    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: false,
      );
      _port = _server!.port;
    } catch (e) {
      _server = null;
      // "Port is busy" was shown for every failure; a missing permission or a
      // network that never came up needed a different sentence.
      _lastStartError = _describeBindError(e);
      return false;
    }
    _lastStartError = null;
    if (_advertisedIp.isEmpty) {
      _advertisedIp = await _resolveLanIp();
    }
    _server!.listen(
      _handle,
      onError: (_) {/* a failed request must not kill the classroom */},
      cancelOnError: false,
    );
    return true;
  }

  Future<void> stop() async {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    for (final socket in _sockets.toList()) {
      try {
        socket.sink.close();
      } catch (_) {/* already gone */}
    }
    _sockets.clear();
    _socketsById.clear();
    _participants.clear();
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {/* nothing else to do */}
    }
    _session = null;
    // A restarted host must not inherit yesterday's document: leaving the
    // name and token behind made the first snapshot of a fresh session point
    // at a file that was already unshared.
    clearDocument();
    _documentId = '';
    _page = 1;
    _totalPages = 0;
    _syncPaused = false;
  }

  /// Makes the teacher's picked file readable by students. Only the file that is
  /// currently shared is served, so the rest of the phone stays private.
  ///
  /// A fresh unguessable token goes with it: the download URL travels to every
  /// joined student, so anyone else on the hotspot who types the filename must
  /// not be able to read the teacher's document.
  void registerDocument(String name, String path) {
    _documentName = name;
    _documentPath = path;
    _fileToken = _code();
  }

  void clearDocument() {
    _documentName = '';
    _documentPath = '';
    // Ending sharing must invalidate the old URL: a student who kept it must
    // not still be able to pull the file after the teacher unshared it.
    _fileToken = '';
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    try {
      if (path == '/api/ping') {
        return await _json(request, 200, {'ok': true, 'app': 'classcast'});
      }
      if (path == '/api/session') {
        return await _sessionEndpoint(request);
      }
      if (path == '/api/page') {
        return await _pageEndpoint(request);
      }
      if (path == '/api/document') {
        return await _documentEndpoint(request);
      }
      if (path == '/api/pause') {
        return await _pauseEndpoint(request);
      }
      if (path == '/api/end') {
        return await _endEndpoint(request);
      }
      if (path == '/api/take-control') {
        return await _takeControlEndpoint(request);
      }
      if (path == '/ws') {
        return await _websocket(request);
      }
      if (path.startsWith('/files/')) {
        return await _serveFile(request, path.substring('/files/'.length));
      }
      if (path.startsWith('/s/')) {
        return await _landingPage(request, path.substring('/s/'.length));
      }
      return await _text(request, 404, 'not found');
    } catch (_) {
      // Never let one bad request take the classroom down.
      try {
        return await _json(request, 500, {'ok': false, 'error': 'host error'});
      } catch (_) {
        return;
      }
    }
  }

  // --- API -----------------------------------------------------------------

  Future<void> _sessionEndpoint(HttpRequest request) async {
    if (request.method == 'GET') {
      final id = request.uri.queryParameters['id'] ?? '';
      if (_session == null || _session!['id'] != id) {
        return _json(request, 404, {'ok': false, 'error': 'Session unavailable'});
      }
      return _json(request, 200, {'ok': true, 'session': _snapshot()});
    }

    final body = await _readJson(request);
    final key = body['teacherKey'] as String?;
    if (_session != null && key != _teacherKey) {
      return _json(request, 403, {'ok': false, 'error': 'Permission denied'});
    }
    if (_session == null && (key == null || key.isEmpty)) {
      _teacherKey = _code();
    } else if (key != null && key.isNotEmpty) {
      _teacherKey = key;
    }
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
    return _json(request, 200, {
      'ok': true,
      'session': _snapshot(),
      'teacherKey': _teacherKey,
    });
  }

  Future<void> _pageEndpoint(HttpRequest request) async {
    if (request.method != 'POST') {
      return _json(request, 405, {'ok': false, 'error': 'POST only'});
    }
    final body = await _readJson(request);
    if (!_checkTeacher(body)) {
      return _json(request, 403, {'ok': false, 'error': 'Permission denied'});
    }
    final total = (body['totalPages'] as num?)?.toInt() ?? 0;
    if (total > 0) _totalPages = total;
    final page = (body['page'] as num?)?.toInt() ?? _page;
    _page = _totalPages > 0 ? page.clamp(1, _totalPages).toInt() : page;
    _broadcast(_snapshotEvent('page_changed'));
    return _json(request, 200, {'ok': true, 'session': _snapshot()});
  }

  Future<void> _documentEndpoint(HttpRequest request) async {
    if (request.method != 'POST') {
      return _json(request, 405, {'ok': false, 'error': 'POST only'});
    }
    final body = await _readJson(request);
    if (!_checkTeacher(body)) {
      return _json(request, 403, {'ok': false, 'error': 'Permission denied'});
    }
    if (body['clear'] == true) {
      clearDocument();
      _documentId = '';
      _totalPages = 0;
      _page = 1;
      _broadcast(_snapshotEvent('document_changed'));
      return _json(request, 200, {'ok': true, 'session': _snapshot()});
    }
    final name = body['documentName'] as String? ?? '';
    if (name.isEmpty) {
      return _json(request, 400,
          {'ok': false, 'error': 'documentName is required'});
    }
    if (!_isServable(name)) {
      // Refuse to announce a document this phone cannot actually hand over,
      // so the teacher sees the error instead of every student getting a blank
      // page.
      return _json(request, 404, {
        'ok': false,
        'error': 'This file is not available to the host any more',
      });
    }
    _documentId = body['documentId'] as String? ?? '';
    final declared = (body['totalPages'] as num?)?.toInt() ?? 0;
    _totalPages = declared > 0 ? declared : 0;
    _page = 1;
    _broadcast(_snapshotEvent('document_changed'));
    return _json(request, 200, {'ok': true, 'session': _snapshot()});
  }

  Future<void> _pauseEndpoint(HttpRequest request) async {
    if (request.method != 'POST') {
      return _json(request, 405, {'ok': false, 'error': 'POST only'});
    }
    final body = await _readJson(request);
    if (!_checkTeacher(body)) {
      return _json(request, 403, {'ok': false, 'error': 'Permission denied'});
    }
    _syncPaused = body['paused'] as bool? ?? !_syncPaused;
    _broadcast(_snapshotEvent('session_state'));
    return _json(request, 200, {'ok': true, 'session': _snapshot()});
  }

  Future<void> _endEndpoint(HttpRequest request) async {
    if (request.method != 'POST') {
      return _json(request, 405, {'ok': false, 'error': 'POST only'});
    }
    final body = await _readJson(request);
    if (!_checkTeacher(body)) {
      return _json(request, 403, {'ok': false, 'error': 'Permission denied'});
    }
    _broadcast({
      'type': 'session_ended',
      'sessionId': _session?['id'] ?? '',
    });
    _session = null;
    // The class is over: unshare the file (a kept URL must stop working),
    // forget the roster, and close the students' sockets. Leaving them open
    // meant a student who never left the page stayed connected to a host
    // that had already refused every new join.
    clearDocument();
    _documentId = '';
    _page = 1;
    _totalPages = 0;
    _syncPaused = false;
    _participants.clear();
    _presenceTimer?.cancel();
    _presenceTimer = null;
    for (final socket in _sockets.toList()) {
      try {
        socket.sink.close();
      } catch (_) {/* already gone */}
    }
    _sockets.clear();
    _socketsById.clear();
    return _json(request, 200, {'ok': true});
  }

  /// Pull a student's screen back to the class page.
  ///
  /// With a participant id it reaches that one student; without, every student
  /// gets it. Either way it carries the page to land on, so the student does
  /// not have to wait for the next class page change to notice.
  Future<void> _takeControlEndpoint(HttpRequest request) async {
    if (request.method != 'POST') {
      return _json(request, 405, {'ok': false, 'error': 'POST only'});
    }
    final body = await _readJson(request);
    if (!_checkTeacher(body)) {
      return _json(request, 403, {'ok': false, 'error': 'Permission denied'});
    }
    final pid = body['participantId'] as String? ?? '';
    final frame = jsonEncode({
      'type': 'take_control',
      'sessionId': _session?['id'] ?? '',
      if (pid.isNotEmpty) 'participantId': pid,
      'page': _page,
      'totalPages': _totalPages,
    });
    var sent = 0;
    if (pid.isEmpty) {
      for (final socket in _socketsById.values) {
        try {
          socket.sink.add(frame);
          sent++;
        } catch (_) {/* that student just left */}
      }
    } else {
      final socket = _socketsById[pid];
      if (socket != null) {
        try {
          socket.sink.add(frame);
          sent = 1;
        } catch (_) {/* that student just left */}
      }
    }
    return _json(request, 200, {'ok': true, 'notified': sent});
  }

  // --- websocket -----------------------------------------------------------
  Future<void> _websocket(HttpRequest request) async {
    final sessionId = request.uri.queryParameters['session'] ?? '';
    final name = _cleanName(request.uri.queryParameters['name']);
    final device = request.uri.queryParameters['device'] ?? '';
    final claimsTeacher = request.uri.queryParameters['role'] == 'teacher';
    // Validate before the upgrade: a wrong or ended session must never see a
    // snapshot or appear in the roster.
    if (_session == null) {
      return await _text(request, 403, 'No session is running');
    }
    if (sessionId.isEmpty || sessionId != _session!['id']) {
      return await _text(request, 403, 'Unknown session');
    }
    // Asking for the teacher role is a claim, not a fact. Without the key it
    // is refused, so `?role=teacher` is not a free roster subscription.
    final isTeacher = claimsTeacher &&
        request.uri.queryParameters['key'] == _teacherKey &&
        _teacherKey.isNotEmpty;
    if (claimsTeacher && !isTeacher) {
      return await _text(request, 403, 'Teacher key required');
    }

    final socket = await WebSocketTransformer.upgrade(request);
    final channel = IOWebSocketChannel(socket);
    _sockets.add(channel);
    channel.sink.add(jsonEncode(_snapshotEvent('session_state')));
    // The teacher's own socket subscribes to the roster but is never listed as
    // a participant, so it has no id.
    final pid = isTeacher ? '' : 'ws-${DateTime.now().microsecondsSinceEpoch}';
    if (isTeacher) {
      // Replay who is already in the room. The teacher's socket drops and
      // re-opens whenever the network changes, and without this the roster
      // stood empty for the rest of the lesson even though the students never
      // went anywhere: they had joined before the socket came back.
      for (final participant in _participants.values) {
        channel.sink.add(jsonEncode({
          'type': 'participant_joined',
          'sessionId': sessionId,
          'participantId': participant['id'],
          'participantName': participant['name'],
        }));
      }
    } else {
      _participants[pid] = {
        'id': pid,
        'name': name,
        'device': device,
        'lastSeen': DateTime.now(),
      };
      _socketsById[pid] = channel;
      _ensurePresenceSweep();
      _broadcast({
        'type': 'participant_joined',
        'sessionId': sessionId,
        'participantId': pid,
        'participantName': name,
      });
    }
    channel.stream.listen(
      (frame) => _onFrame(channel, pid, sessionId, frame),
      onDone: () => _onClose(channel, pid, sessionId),
      onError: (_) => _onClose(channel, pid, sessionId),
      cancelOnError: false,
    );
  }

  void _onFrame(
    WebSocketChannel channel,
    String pid,
    String sessionId,
    Object? frame,
  ) {
    Map<String, dynamic>? message;
    try {
      message = Map<String, dynamic>.from(jsonDecode(frame as String) as Map);
    } catch (_) {
      return;
    }
    // Students must not drive the presentation: the class page is teacher
    // control only, over REST with the teacher key. They may, however, *ask*
    // for attention and report where they are, and those have to reach the
    // teacher's screen — a hand raised that the teacher never sees is a
    // broken feature.
    //
    // These case labels are the client's wire names, taken from
    // `SyncEventType.wire`. They were 'raise_hand' / 'lower_hand' /
    // 'student_page', which the client has never sent, so every frame a student
    // sent fell through to `default: return` and the feature was dead in both
    // directions without anything ever saying so.
    // Any frame at all is proof of life, so the presence clock resets first.
    _touch(pid);
    final name = _cleanName(message['participantName'] as String?);
    switch (message['type']) {
      case 'heartbeat':
        // Purely a liveness ping; the touch above is the whole effect.
        return;
      case 'join':
        _participants[pid] = {
          'id': pid,
          'name': name,
          'device': message['message'] ?? '',
          'lastSeen': DateTime.now(),
        };
        _socketsById[pid] = channel;
        _ensurePresenceSweep();
        channel.sink.add(jsonEncode(_snapshotEvent('session_state')));
        _broadcast({
          'type': 'participant_joined',
          'sessionId': sessionId,
          'participantId': pid,
          'participantName': name,
        });
        return;
      case 'hand_raised':
        if (pid.isEmpty) return;
        // The teacher tracks hands from the broadcast; the host keeps no copy.
        _broadcast({
          'type': 'hand_raised',
          'sessionId': sessionId,
          'participantId': pid,
          'participantName': _participants[pid]?['name'] ?? name,
        });
        return;
      case 'hand_lowered':
        if (pid.isEmpty) return;
        _broadcast({
          'type': 'hand_lowered',
          'sessionId': sessionId,
          'participantId': pid,
          'participantName': _participants[pid]?['name'] ?? name,
        });
        return;
      case 'student_page_changed':
        if (pid.isEmpty) return;
        final page = (message['page'] as num?)?.toInt();
        if (page == null) return;
        // Reported, not applied: the teacher sees where this student is.
        _broadcast({
          'type': 'student_page_changed',
          'sessionId': sessionId,
          'participantId': pid,
          'participantName': _participants[pid]?['name'] ?? name,
          'page': page,
          'totalPages': _totalPages,
        });
        return;
      default:
        return;
    }
  }

  void _onClose(WebSocketChannel channel, String pid, String sessionId) {
    _sockets.remove(channel);
    if (pid.isEmpty) return;
    _socketsById.remove(pid);
    // Forgetting the participant too, not just its socket. A student who
    // reconnected got a fresh id, and the old entry lived on in this map
    // forever, ready to be replayed to the teacher as if they were still in
    // the room.
    if (_participants.remove(pid) == null) return;
    _stopSweepWhenEmpty();

    _broadcast({
      'type': 'participant_left',
      'sessionId': sessionId,
      'participantId': pid,
    });
  }

  /// Any frame from a student proves they are still there, so the sweep's
  /// clock resets on all of them — not just heartbeats.
  void _touch(String pid) {
    _participants[pid]?['lastSeen'] = DateTime.now();
  }

  /// Starts the sweep when the first student registers. A room with nobody in
  /// it needs no timer.
  void _ensurePresenceSweep() {
    if (_presenceTimer != null || _participants.isEmpty) return;
    _presenceTimer = Timer.periodic(sweepInterval, (_) => _sweepPresence());
  }

  void _stopSweepWhenEmpty() {
    if (_participants.isNotEmpty) return;
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  /// Drops students whose socket has been silent past [presenceTimeout].
  ///
  /// This is the half-open connection case: the TCP session still looks alive
  /// (no FIN ever arrived), so the onDone/onError paths never fire, and the
  /// teacher keeps seeing a student who left the hotspot long ago.
  void _sweepPresence() {
    final cutoff = DateTime.now().subtract(presenceTimeout);
    final stale = <String>[];
    for (final entry in _participants.entries) {
      final seen = entry.value['lastSeen'];
      if (seen is DateTime && seen.isBefore(cutoff)) stale.add(entry.key);
    }
    for (final pid in stale) {
      final socket = _socketsById.remove(pid);
      _participants.remove(pid);
      if (socket != null) {
        _sockets.remove(socket);
        try {
          socket.sink.close();
        } catch (_) {/* already gone */}
      }
      // Exactly the frame a clean disconnect would have produced, so the
      // teacher's roster stays honest without any new client handling.
      _broadcast({
        'type': 'participant_left',
        'sessionId': _session?['id'] ?? '',
        'participantId': pid,
      });
    }
    _stopSweepWhenEmpty();
  }

  // --- files ---------------------------------------------------------------

  Future<void> _serveFile(HttpRequest request, String requested) async {
    // The request-target arrives percent-encoded (`great%20slides.pdf`).
    // Decode exactly once to match the name the teacher registered. A
    // malformed escape used to throw out of the handler and paint a 500 for
    // any device on the hotspot that asked for `/files/%`; it is simply a
    // miss.
    String name;
    try {
      name = Uri.decodeComponent(requested);
    } catch (_) {
      return await _text(request, 404, 'not found');
    }
    // The session must be running, and the request must carry the token the
    // snapshot handed out. Without both, anyone on the hotspot who guessed the
    // filename could read the teacher's document.
    if (_session == null) return await _text(request, 403, 'No session');
    if (_fileToken.isEmpty ||
        request.uri.queryParameters['t'] != _fileToken) {
      return await _text(request, 403, 'Not allowed');
    }
    if (!_isServable(name)) return await _text(request, 404, 'not found');
    final file = File(_documentPath);
    final length = await file.length();
    request.response.headers
      ..set(HttpHeaders.contentTypeHeader, _mimeFor(name))
      ..set(HttpHeaders.contentLengthHeader, '$length')
      // The shared document changes as the teacher moves on.
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      // A student's browser may live on a different origin; the bytes are
      // still local-network only, so the browser is allowed to read them.
      ..set('access-control-allow-origin', '*')
      // Always inline: viewing the current document is the whole point.
      ..set('content-disposition', 'inline');
    if (request.method == 'HEAD') {
      return request.response.close();
    }
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  /// Tiny landing page, so a student who scans the QR with the phone *browser*
  /// (not the app) is told what to do instead of getting a 404.
  Future<void> _landingPage(HttpRequest request, String sessionId) async {
    request.response.headers.contentType = ContentType.html;
    final id = _session?['id'] ?? sessionId;
    request.response.write('''
<!doctype html>
<html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ClassCast Classroom</title>
<style>
 body{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:#F6F8FC;
      color:#14213D;display:flex;align-items:center;justify-content:center;
      height:100vh;margin:0;text-align:center;padding:24px}
 .card{background:#fff;border-radius:20px;padding:32px 24px;max-width:420px;
       box-shadow:0 8px 30px rgba(20,33,61,.12)}
 h1{font-size:20px;margin:0 0 8px} p{color:#7C879D;font-size:14px;line-height:1.5}
 code{background:#E6EDFF;padding:2px 8px;border-radius:8px;color:#2549B8}
</style></head>
<body><div class="card">
 <h1>ClassCast classroom is live</h1>
 <p>Session <code>$id</code> is being taught from the teacher's phone.</p>
 <p>Open the <b>ClassCast</b> app, choose <b>Student</b>, then scan this code —
 the document the teacher shares will appear here automatically.</p>
</div></body></html>''');
    await request.response.close();
  }

  // --- helpers -------------------------------------------------------------

  bool _checkTeacher(Map<String, dynamic> body) {
    if (_session == null) return false;
    if (_teacherKey.isEmpty) return false;
    return body['teacherKey'] == _teacherKey;
  }

  /// True only for the exact file the teacher is currently sharing.
  bool _isServable(String name) {
    if (_documentName.isEmpty || _documentPath.isEmpty) return false;
    if (name != _documentName) return false;
    if (name.contains('/') || name.contains('\\')) return false;
    try {
      return File(_documentPath).existsSync();
    } catch (_) {
      return false;
    }
  }

  static String _mimeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.'
          'presentationml.presentation';
    }
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.'
          'wordprocessingml.document';
    }
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.'
          'spreadsheetml.sheet';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  Map<String, dynamic> _snapshot() => {
        if (_session != null) ..._session!,
        'hostIp': _advertisedIp,
        'port': _port,
        'documentId': _documentId.isEmpty ? null : _documentId,
        'documentName': _documentName.isEmpty ? null : _documentName,
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

  String? _documentUrl() {
    if (_documentName.isEmpty) return null;
    final encoded = Uri.encodeComponent(_documentName);
    final suffix = _fileToken.isEmpty ? '' : '?t=$_fileToken';
    if (_advertisedIp.isEmpty) return '/files/$encoded$suffix';
    return 'http://$_advertisedIp:$_port/files/$encoded$suffix';
  }

  void _broadcast(Map<String, dynamic> event) {
    final frame = jsonEncode(event);
    for (final socket in _sockets.toList()) {
      try {
        socket.sink.add(frame);
      } catch (_) {
        // A sink that failed to accept is dead. Removing it from the set is
        // not enough — the underlying socket stayed open, and one dead
        // connection per dead student adds up over a school day.
        _sockets.remove(socket);
        _forgetSocket(socket);
        try {
          socket.sink.close();
        } catch (_) {/* already gone */}
      }
    }
  }

  /// Drops every map entry pointing at [socket], so a dead connection cannot
  /// linger as a stale target for take control.
  void _forgetSocket(WebSocketChannel socket) {
    _socketsById.removeWhere((_, value) => identical(value, socket));
  }

  /// A roster name comes straight off the wire, so it gets bounded: one
  /// student cannot fill the teacher's screen with a megabyte of text or
  /// impersonate another entry with stray whitespace.
  static String _cleanName(String? raw) {
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return 'Student';
    return trimmed.length <= 32 ? trimmed : trimmed.substring(0, 32);
  }

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    try {
      // Every control endpoint takes a handful of short strings. Reading a
      // body without a cap let a device on the hotspot make the teacher's
      // phone buffer an arbitrarily large request.
      final text = await utf8.decoder
          .bind(request)
          .take(_maxBodyBytes)
          .join();
      if (text.isEmpty) return {};
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  /// 64 KB is far above any real control frame and far below anything that
  /// could hurt the phone.
  static const int _maxBodyBytes = 64 * 1024;

  Future<void> _json(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    // The classroom is a local network; the browser build may live on another
    // origin, so the API answers cross-origin reads.
    request.response.headers.set('access-control-allow-origin', '*');
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _text(HttpRequest request, int status, String body) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.text;
    request.response.write(body);
    await request.response.close();
  }

  /// The key a caller did not supply.
  ///
  /// This used to be six characters sliced out of the millisecond timestamp,
  /// which is a function of one observable number: knowing roughly when the
  /// session started left a few thousand candidates to try. `Random.secure()`
  /// is not slower in any way a teacher can perceive.
  String _code() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = _random ??= Random.secure();
    return List.generate(
        8, (i) => chars[rnd.nextInt(chars.length)]).join();
  }

  Random? _random;

  /// Picks the address students can actually reach.
  ///
  /// Taking the first non-loopback IPv4 is wrong on a typical phone: VPN and
  /// "wlan0"/"ap0" confusion is common, and a virtual adapter hands students an
  /// address that routes nowhere.
  static Future<String> _resolveLanIp() async {
    const virtualHints = <String>[
      'loopback', 'vmware', 'virtualbox', 'vethernet', 'hyper-v', 'docker',
      'wsl', 'tailscale', 'zerotier', 'bluetooth', 'vpn', 'ppp', 'rmnet',
    ];
    String? fallback;
    try {
      final interfaces =
          await NetworkInterface.list(includeLoopback: false);
      for (final nic in interfaces) {
        for (final addr in nic.addresses) {
          if (addr.isLoopback) continue;
          if (addr.type != InternetAddressType.IPv4) continue;
          final name = nic.name.toLowerCase();
          // Android hotspots live on wlan0 / ap0 — those are the good ones.
          final isHotspot = name.startsWith('wlan') || name.startsWith('ap');
          final isVirtual =
              virtualHints.any(name.contains) || name.startsWith('tun');
          if (isVirtual) continue;
          final ip = addr.address;
          if (isHotspot) return ip;
          fallback ??= ip;
        }
      }
    } catch (_) {
      // Enumeration is best-effort.
    }
    return fallback ?? '';
  }
}
