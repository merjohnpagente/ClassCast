import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/classroom_session.dart';
import '../models/participant.dart';
import '../models/shared_document.dart';
import '../models/sync_event.dart';
import '../services/session_store.dart';
import '../services/sync_protocol.dart';
import '../services/teacher_host_client.dart';

/// Teacher-side session state: create / end / page / document / participants.
/// With a real host, page/document changes are also broadcast over WS
/// (see `server/` + [SyncProvider] on the student side).
class SessionProvider extends ChangeNotifier {
  static const _uuid = Uuid();
  final SessionStore _store = SessionStore();

  /// Controls the laptop host so students actually receive the broadcast.
  final TeacherHostClient _host = TeacherHostClient();

  bool _disposed = false;

  SessionProvider() {
    // Repaint the host-status chip whenever a control call finishes.
    _host.onStatusChanged = _safeNotify;
  }

  @override
  void dispose() {
    _disposed = true;
    _closeHostEvents();
    super.dispose();
  }

  // --- teacher event link -------------------------------------------------
  //
  // The teacher holds a WebSocket to the host purely to *receive* join/leave
  // notifications. Control still goes over the REST API with the teacher key,
  // so a compromised socket cannot drive the presentation.

  WebSocketChannel? _hostSocket;
  StreamSubscription<dynamic>? _hostEvents;

  void _openHostEvents(ClassroomSession s) {
    _closeHostEvents();
    if (s.hostIp.isEmpty) return;
    try {
      final channel = WebSocketChannel.connect(SyncProtocol.wsUri(
        host: s.hostIp,
        port: s.port,
        sessionId: s.id,
        name: 'Teacher',
        role: 'teacher',
      ));
      _hostSocket = channel;
      _hostEvents = channel.stream.listen((frame) {
        final event = SyncProtocol.decode(frame);
        if (event != null) applyEvent(event);
      }, onError: (_) {}, cancelOnError: false);
    } catch (_) {
      // Standalone teacher mode: no host, so no live roster.
      _hostSocket = null;
      _hostEvents = null;
    }
  }

  void _closeHostEvents() {
    _hostEvents?.cancel();
    _hostEvents = null;
    try {
      _hostSocket?.sink.close();
    } catch (_) {/* ignore */}
    _hostSocket = null;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// False when the last control call could not reach the host. The UI shows
  /// this honestly instead of implying students are in sync.
  bool get hostReachable => _host.lastCallOk;
  String? get hostError => _host.lastError;

  ClassroomSession? _active;
  ClassroomSession? get active => _active;

  List<ClassroomSession> _recent = [];
  List<ClassroomSession> get recent => List.unmodifiable(_recent);

  List<Participant> _participants = [];
  List<Participant> get participants => List.unmodifiable(_participants);

  bool _loaded = false;
  bool get isLoaded => _loaded;

  int get connectedCount => _participants
      .where((p) => p.status == Presence.connected)
      .length;

  /// Load sessions saved on this device (SQLite). No sample data.
  Future<void> load() async {
    _recent = await _store.loadRecent();
    _participants = [];
    _loaded = true;
    notifyListeners();
  }

  /// Create + start a local session. No cloud required.
  Future<ClassroomSession> createSession({
    required String name,
    String subject = '',
    String hostIp = '',
    int port = 8080,
    bool allowAnonymous = true,
    bool allowDownload = false,
    bool allowStudentNav = false,
  }) async {
    final id = _newSessionId();
    final session = ClassroomSession(
      id: id,
      name: name.trim(),
      subject: subject.trim(),
      hostIp: hostIp,
      port: port,
      createdAt: DateTime.now(),
      allowAnonymous: allowAnonymous,
      allowDownload: allowDownload,
      allowStudentNav: allowStudentNav,
      isActive: true,
      teacherKey: _uuid.v4().substring(0, 8),
    );
    _active = session;
    await _store.saveSession(session);
    _recent = await _store.loadRecent();
    notifyListeners();
    // Register the session on the host so students can join it, and listen
    // for the roster events it broadcasts back.
    unawaited(_host.startSession(session));
    _openHostEvents(session);
    return session;
  }

  Future<void> endSession() async {
    if (_active == null) return;
    final ending = _active!;
    unawaited(_host.endSession(ending));
    _closeHostEvents();
    final ended = ending.copyWith(isActive: false);
    await _store.saveSession(ended);
    _recent = await _store.loadRecent();
    _active = null;
    _participants = [];
    notifyListeners();
  }

  void setNetwork({required String hostIp, required int port}) {
    if (_active == null) return;
    _active = _active!.copyWith(hostIp: hostIp, port: port);
    notifyListeners();
    _openHostEvents(_active!);
  }

  void shareDocument(SharedDocument doc, {int totalPages = 0}) {
    if (_active == null) return;
    final pages = totalPages > 0 ? totalPages : doc.pageCount;
    // The host keys the file off its name, so it must match what is in the
    // shared directory exactly.
    final fileName =
        '${doc.name}${doc.extension.isEmpty ? '' : '.${doc.extension}'}';
    _active = _active!.copyWith(
      documentId: () => doc.id,
      documentName: () => fileName,
      page: 1,
      totalPages: pages,
    );
    notifyListeners();
    unawaited(_host.shareDocument(
      _active!,
      documentId: doc.id,
      documentName: fileName,
      totalPages: pages,
    ));
  }

  void clearDocument() {
    if (_active == null) return;
    _active = _active!
        .copyWith(documentId: () => null, documentName: () => null);
    notifyListeners();
    // Tell the host too, otherwise students keep rendering the old file.
    unawaited(_host.clearDocument(_active!));
  }

  /// Teacher pressed a navigation control: update locally, then broadcast.
  void setPage(int page) {
    final next = _applyPage(page);
    if (next == null) return;
    unawaited(_host.setPage(_active!, next));
  }

  /// Local-only page move. Used when applying an inbound event so the host
  /// is not echoed back to itself.
  void _setPageLocal(int page) => _applyPage(page);

  int? _applyPage(int page) {
    if (_active == null) return null;
    final total = _active!.totalPages;
    final clamped = total <= 0 ? page : page.clamp(1, total);
    _active = _active!.copyWith(page: clamped);
    notifyListeners();
    return clamped;
  }

  /// Freeze / resume student screens. Single source of truth lives on the
  /// session, so teacher and students agree.
  void setPaused(bool paused) {
    if (_active == null) return;
    _active = _active!.copyWith(syncPaused: paused);
    notifyListeners();
    unawaited(_host.setPaused(_active!, paused));
  }

  /// Apply an incoming sync event (student echo / host broadcast).
  void applyEvent(SyncEvent event) {
    if (_active == null || event.sessionId != _active!.id) return;
    switch (event.type) {
      case SyncEventType.pageChanged:
        if (event.page != null) _setPageLocal(event.page!);
        break;
      case SyncEventType.documentChanged:
        _active = _active!.copyWith(
          documentId: () => event.documentId,
          documentName: () => event.documentName,
          page: event.page ?? 1,
          totalPages: event.totalPages ?? _active!.totalPages,
        );
        notifyListeners();
        break;
      case SyncEventType.sessionEnded:
        endSession();
        break;
      case SyncEventType.participantJoined:
        if (event.participantName != null) {
          addParticipant(Participant(
            id: event.participantId ??
                'stu-${DateTime.now().millisecondsSinceEpoch}',
            name: event.participantName!,
            deviceType: event.message ?? 'Android',
            joinedAt: DateTime.now(),
          ));
        }
        break;
      case SyncEventType.participantLeft:
        if (event.participantId != null) {
          removeParticipant(event.participantId!);
        }
        break;
      case SyncEventType.join:
      case SyncEventType.sessionState:
      case SyncEventType.connectionStatus:
        break;
    }
  }

  void addParticipant(Participant p) {
    if (_participants.any((e) => e.id == p.id)) return;
    _participants = [..._participants, p];
    notifyListeners();
  }

  void removeParticipant(String id) {
    _participants = _participants.where((p) => p.id != id).toList();
    notifyListeners();
  }

  String _newSessionId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final code =
        List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'CLASS-$code';
  }
}
