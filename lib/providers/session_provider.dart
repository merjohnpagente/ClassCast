import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/classroom_session.dart';
import '../models/participant.dart';
import '../models/shared_document.dart';
import '../models/sync_event.dart';
import '../services/session_store.dart';

/// Teacher-side session state: create / end / page / document / participants.
/// With a real host, page/document changes are also broadcast over WS
/// (see `server/` + [SyncProvider] on the student side).
class SessionProvider extends ChangeNotifier {
  static const _uuid = Uuid();
  final SessionStore _store = SessionStore();

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
    return session;
  }

  Future<void> endSession() async {
    if (_active == null) return;
    final ended = _active!.copyWith(isActive: false);
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
  }

  void shareDocument(SharedDocument doc, {int totalPages = 0}) {
    if (_active == null) return;
    _active = _active!.copyWith(
      documentId: () => doc.id,
      documentName: () => '${doc.name}'
          '${doc.extension.isEmpty ? '' : '.${doc.extension}'}',
      page: 1,
      totalPages: totalPages > 0 ? totalPages : doc.pageCount,
    );
    notifyListeners();
  }

  void clearDocument() {
    if (_active == null) return;
    _active = _active!
        .copyWith(documentId: () => null, documentName: () => null);
    notifyListeners();
  }

  void setPage(int page) {
    if (_active == null) return;
    final total = _active!.totalPages;
    final clamped =
        total <= 0 ? page : page.clamp(1, total);
    _active = _active!.copyWith(page: clamped);
    notifyListeners();
  }

  /// Apply an incoming sync event (student echo / host broadcast).
  void applyEvent(SyncEvent event) {
    if (_active == null || event.sessionId != _active!.id) return;
    switch (event.type) {
      case SyncEventType.pageChanged:
        if (event.page != null) setPage(event.page!);
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
