import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/classroom_session.dart';
import '../models/sync_event.dart';
import 'sync_protocol.dart';

/// Connection state shown in the UI. `live` is set ONLY after the host
/// answers (REST snapshot) or the WebSocket opens — never speculatively.
enum LinkState { idle, connecting, live, reconnecting, offline, ended, error }

/// Student-side client: REST snapshot + WebSocket live updates with
/// automatic re-subscribe and graceful reconnect.
class ClasscastClient {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  int _attempt = 0;

  final _events = StreamController<SyncEvent>.broadcast();
  Stream<SyncEvent> get events => _events.stream;

  LinkState _state = LinkState.idle;
  LinkState get state => _state;

  final _stateCtrl = StreamController<LinkState>.broadcast();
  Stream<LinkState> get stateChanges => _stateCtrl.stream;

  void _setState(LinkState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  /// Fetch the authoritative session snapshot over local HTTP.
  Future<ClassroomSession?> fetchSnapshot({
    required String host,
    required int port,
    required String sessionId,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final res = await http
          .get(SyncProtocol.sessionUri(
              host: host, port: port, sessionId: sessionId))
          .timeout(timeout);
      if (res.statusCode != 200) return null;
      final map = Map<String, dynamic>.from(
          jsonDecode(res.body) as Map);
      if (map['ok'] == false) return null;
      final data = map['session'] is Map
          ? Map<String, dynamic>.from(map['session'] as Map)
          : map;
      return ClassroomSession.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Sends a student-initiated frame over the live channel.
  ///
  /// Students never drive the class page — that stays teacher-only, over
  /// REST with the teacher key. They do raise a hand and report where they
  /// are, and those have to reach the teacher's screen.
  bool send(SyncEvent event) {
    final channel = _channel;
    if (channel == null) return false;
    try {
      channel.sink.add(SyncProtocol.encode(event));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Open the live channel, from scratch. Reconnects with backoff on drops.
  ///
  /// This is the deliberate entry point, so it starts the backoff over. The
  /// retry path calls [_open] directly instead, which is what stops every
  /// attempt from resetting the counter and pinning the delay at two seconds.
  void subscribe({
    required String host,
    required int port,
    required String sessionId,
    String name = '',
    String device = '',
  }) {
    _open(
      host: host,
      port: port,
      sessionId: sessionId,
      name: name,
      device: device,
      resetBackoff: true,
    );
  }

  void _open({
    required String host,
    required int port,
    required String sessionId,
    required bool resetBackoff,
    String name = '',
    String device = '',
  }) {
    _stopReconnect();
    _setState(LinkState.connecting);
    if (resetBackoff) _attempt = 0;
    // The previous channel's socket has to actually close. Cancelling the
    // subscription only stops delivery; the underlying WebSocket stayed open,
    // so every retry abandoned a live TCP connection and the host collected
    // them as dead entries in its socket set.
    _teardown();
    try {
      final channel = WebSocketChannel.connect(
        SyncProtocol.wsUri(
            host: host,
            port: port,
            sessionId: sessionId,
            name: name,
            device: device),
      );
      _channel = channel;
      // Hello frame so the server registers this participant.
      channel.sink.add(SyncProtocol.encode(SyncEvent(
        type: SyncEventType.join,
        sessionId: sessionId,
        participantName: name,
        message: device,
      )));
      _sub = channel.stream.listen(
        (frame) {
          // "Live" means the host answered, not that we asked. connect()
          // returns a channel object immediately, so marking it live here
          // showed a green "live" chip to students who were not connected.
          if (_state != LinkState.live) _setState(LinkState.live);
          final event = SyncProtocol.decode(frame);
          if (event != null && !_events.isClosed) _events.add(event);
        },
        onError: (_) => _scheduleReconnect(
            host: host, port: port, sessionId: sessionId,
            name: name, device: device),
        onDone: () {
          if (_state == LinkState.live || _state == LinkState.connecting) {
            _scheduleReconnect(
                host: host, port: port, sessionId: sessionId,
                name: name, device: device);
          }
        },
        cancelOnError: false,
      );
    } catch (_) {
      _scheduleReconnect(
          host: host, port: port, sessionId: sessionId,
          name: name, device: device);
    }
  }

  void _scheduleReconnect({
    required String host,
    required int port,
    required String sessionId,
    String name = '',
    String device = '',
  }) {
    _setState(LinkState.reconnecting);
    _stopReconnect();
    _attempt++;
    final wait =
        Duration(seconds: _attempt >= 5 ? 10 : 2 * _attempt);
    _reconnectTimer = Timer(wait, () {
      if (_state == LinkState.ended) return;
      // resetBackoff: false, or this is the flat two-second loop again.
      _open(
          host: host, port: port, sessionId: sessionId,
          name: name, device: device, resetBackoff: false);
    });
  }

  /// Closes the current channel for real.
  ///
  /// `StreamSubscription.cancel` stops delivery but leaves the socket open, so
  /// every reconnect used to leak one. Nothing here is awaited on purpose: a
  /// close that is slow to finish must not delay the new connection.
  void _teardown() {
    final sub = _sub;
    final channel = _channel;
    _sub = null;
    _channel = null;
    unawaited(sub?.cancel());
    try {
      unawaited(channel?.sink.close());
    } catch (_) {/* already gone */}
  }

  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Leave without reconnecting.
  Future<void> disconnect() async {
    _setState(LinkState.ended);
    _stopReconnect();
    _teardown();
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
    await _stateCtrl.close();
  }
}
