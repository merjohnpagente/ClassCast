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
/// - `GET  /api/document?id=<docId>` — document metadata
/// - `GET  /files/<docId>` — file bytes (when downloads allowed)
/// - `WS   /ws?session=<id>&name=<student>` — live updates
/// - `POST /api/page` (teacher key) — set current page
/// - `POST /api/document` (teacher key) — share a document
class SyncProtocol {
  static const defaultPort = 8080;
  static const wsPath = '/ws';
  static const sessionApi = '/api/session';
  static const documentApi = '/api/document';
  static const pageApi = '/api/page';
  static const shareApi = '/api/document';
  static const filesRoot = '/files';
  static const webJoinPrefix = '/s/';

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

  /// Teacher-only events must carry a teacher key on the server.
  /// Clients use this to avoid sending invalid control frames.
  static bool isTeacherControl(SyncEventType type) {
    return type == SyncEventType.pageChanged ||
        type == SyncEventType.documentChanged ||
        type == SyncEventType.sessionEnded;
  }

  static Uri wsUri({
    required String host,
    required int port,
    required String sessionId,
    String name = '',
    String device = '',
  }) {
    final query = {
      'session': sessionId,
      if (name.isNotEmpty) 'name': name,
      if (device.isNotEmpty) 'device': device,
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
