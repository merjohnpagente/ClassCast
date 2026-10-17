import 'dart:convert';

import '../models/sync_event.dart';

/// Wire protocol shared by the laptop Shelf server (`server/`)
/// and the Flutter clients.
///
/// Message envelope (JSON over WebSocket):
/// ```json
/// {"type": "page_changed", "sessionId": "CLASS-101",
///  "documentId": "d1", "page": 4, "totalPages": 12}
/// ```
///
/// REST endpoints served by the host:
/// - `GET  /api/session?id=CLASS-101` — session snapshot
/// - `POST /api/session` (teacher key) — start / update the session
/// - `POST /api/page` (teacher key) — set current page
/// - `POST /api/document` (teacher key) — share a document
/// - `POST /api/pause` (teacher key) — freeze / resume student screens
/// - `POST /api/end` (teacher key) — end the session
/// - `GET  /files/<name>` — the shared document's bytes
/// - `WS   /ws?session=<id>&name=<student>` — live updates
class SyncProtocol {
  static const defaultPort = 8080;
  static const wsPath = '/ws';
  static const sessionApi = '/api/session';
  static const documentApi = '/api/document';
  static const pageApi = '/api/page';
  static const pauseApi = '/api/pause';
  static const videoApi = '/api/video';
  static const endApi = '/api/end';
  static const takeControlApi = '/api/take-control';

  /// How often a connected student says "still here" while nothing else is
  /// happening. Sent as a [SyncEventType.heartbeat] frame over the live socket.
  static const heartbeatInterval = Duration(seconds: 10);

  /// How long a host waits before dropping a student it has not heard from.
  /// Three missed heartbeats: a phone that slept or slipped off the hotspot
  /// never sends a FIN, so the socket can look open while nobody is there.
  static const presenceTimeout = Duration(seconds: 30);

  /// Encode an event for the socket.
  static String encode(SyncEvent event) => jsonEncode(event.toJson());

  /// Decode an incoming socket frame. Returns null when malformed.
  static SyncEvent? decode(Object? frame) {
    try {
      if (frame is! String) return null;
      final map = Map<String, dynamic>.from(
          jsonDecode(frame) as Map);
      final event = SyncEvent.fromJson(map);
      if (event.sessionId.isEmpty) return null;
      return event;
    } catch (_) {
      return null;
    }
  }

  static Uri wsUri({
    required String host,
    required int port,
    required String sessionId,
    String name = '',
    String device = '',
    String role = '',
    String teacherKey = '',
  }) {
    final query = {
      'session': sessionId,
      if (name.isNotEmpty) 'name': name,
      if (device.isNotEmpty) 'device': device,
      // 'teacher' subscribes to events without joining the student roster. It
      // is a claim, so it carries the key: otherwise anyone on the hotspot
      // could ask for the whole roster by adding this to the URL.
      if (role.isNotEmpty) 'role': role,
      if (teacherKey.isNotEmpty) 'key': teacherKey,
    };
    return Uri(
      scheme: 'ws',
      host: host,
      port: port,
      path: wsPath,
      queryParameters: query,
    );
  }

  static Uri sessionUri({
    required String host,
    required int port,
    required String sessionId,
  }) {
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: sessionApi,
      queryParameters: {'id': sessionId},
    );
  }
}
