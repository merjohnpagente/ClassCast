import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/classroom_session.dart';
import '../models/sync_event.dart';
import '../services/classcast_client.dart';
import '../services/network_service.dart';

/// Student-side live sync: join, snapshot, subscribe, reconnect.
/// Drives the waiting screen -> viewer flow.
class SyncProvider extends ChangeNotifier {
  final ClasscastClient _client = ClasscastClient();
  StreamSubscription? _eventSub;
  StreamSubscription? _stateSub;

  String _host = '';
  String get host => _host;

  int _port = 8080;
  int get port => _port;

  String _sessionId = '';
  String get sessionId => _sessionId;

  String _studentName = '';
  String get studentName => _studentName;

  LinkState _link = LinkState.idle;
  LinkState get link => _link;

  String? _error;
  String? get error => _error;

  bool _hasDocument = false;
  bool get hasDocument => _hasDocument;

  /// Mirrors the teacher's pause so student UI can show the paused chip.
  bool _syncPaused = false;
  bool get syncPaused => _syncPaused;

  /// Authoritative session snapshot for students (from host REST +
  /// live WS events). The teacher's own [SessionProvider] is untouched
  /// in student mode.
  ClassroomSession? _snapshot;
  ClassroomSession? get snapshot => _snapshot;

  Stream<SyncEvent> get events => _client.events;

  SyncProvider() {
    _stateSub = _client.stateChanges.listen((s) {
      _link = s;
      notifyListeners();
    });
  }

  /// Join flow: validate -> probe host -> snapshot -> subscribe.
  /// Returns true only when the host really answers.
  Future<bool> join({
    required String rawInput,
    required String studentName,
    String device = 'Android',
  }) async {
    _error = null;
    _hasDocument = false;
    _snapshot = null;
    _syncPaused = false;
    final parsed = NetworkService.parseJoinInput(rawInput);
    if (parsed == null) {
      _error = 'Enter a Session ID or joining address.';
      notifyListeners();
      return false;
    }
    if (parsed.host.isEmpty) {
      _error = 'Scan the classroom QR or enter the full joining address '
          '(it includes the teacher address).';
      notifyListeners();
      return false;
    }
    if (parsed.sessionId.isEmpty) {
      _error = 'The joining address is missing the session ID.';
      notifyListeners();
      return false;
    }
    _host = parsed.host;
    _port = parsed.port;
    _sessionId = parsed.sessionId;
    _studentName = studentName.trim();
    _link = LinkState.connecting;
    notifyListeners();

    final ok = await NetworkService.probeHost(host: _host, port: _port);
    if (!ok) {
      _link = LinkState.offline;
      _error = 'Session unavailable. Check the hotspot / Wi-Fi and address.';
      notifyListeners();
      return false;
    }

    final snapshot = await _client.fetchSnapshot(
        host: _host, port: _port, sessionId: _sessionId);
    _client.subscribe(
        host: _host,
        port: _port,
        sessionId: _sessionId,
        name: _studentName,
        device: device);
    if (snapshot != null) {
      _snapshot = snapshot;
      _syncPaused = snapshot.syncPaused;
      _hasDocument = snapshot.documentId != null;
    }
    bind();
    _link = LinkState.live;
    notifyListeners();
    return true;
  }

  /// Listen for teacher broadcasts and mirror them into [_snapshot].
  /// Idempotent — safe to call on every build while joined.
  bool _bound = false;
  void bind() {
    if (_bound) return;
    _bound = true;
    _eventSub = _client.events.listen((event) {
      if (event.sessionId != _sessionId) return;
      switch (event.type) {
        case SyncEventType.sessionState:
        case SyncEventType.documentChanged:
        case SyncEventType.pageChanged:
          final base = _snapshot;
          if (base == null) return;
          _snapshot = base.copyWith(
            documentId: () => event.documentId ?? base.documentId,
            documentName: () =>
                event.documentName ?? base.documentName,
            // Must be mirrored too: a student who joined before the teacher
            // shared anything learns the fetch URL from this event alone.
            documentUrl: () => event.documentUrl ?? base.documentUrl,
            page: event.page ?? base.page,
            totalPages: event.totalPages ?? base.totalPages,
            syncPaused: event.syncPaused ?? base.syncPaused,
          );
          if (event.documentId != null) _hasDocument = true;
          _syncPaused = _snapshot!.syncPaused;
          // Following the class again is normal teaching, so the hold is over.
          if (event.page != null) _takenOver = false;
          notifyListeners();
          break;
        case SyncEventType.sessionEnded:
          if (_snapshot != null) {
            _snapshot = _snapshot!.copyWith(isActive: false);
          }
          _link = LinkState.ended;
          notifyListeners();
          break;
        case SyncEventType.handRaised:
        case SyncEventType.handLowered:
        case SyncEventType.studentPageChanged:
          // The teacher mirrors these on their own screen; the student UI
          // only needs its own hand state, tracked locally.
          break;
        case SyncEventType.takeControl:
          // The teacher wants this screen back on the class page. Land on the
          // page they are on now, and hold this student to it until the class
          // page moves again.
          final base = _snapshot;
          if (base == null) return;
          _takenOver = true;
          _snapshot = base.copyWith(
            page: event.page ?? base.page,
            totalPages: event.totalPages ?? base.totalPages,
          );
          notifyListeners();
          break;
        case SyncEventType.participantJoined:
        case SyncEventType.participantLeft:
        case SyncEventType.join:
        case SyncEventType.connectionStatus:
          break;
      }
    });
  }

  /// True while the teacher holds this screen to the class page. Cleared as
  /// soon as the class page moves, because then following it is the point.
  bool _takenOver = false;
  bool get takenOver => _takenOver;

  /// Whether this student may turn pages right now.
  ///
  /// Turned off while taken over: that is what "take control" means, and
  /// letting the student keep turning pages would make it a no-op.
  bool get canNavigate =>
      (_snapshot?.allowStudentNav ?? false) && !_takenOver;

  /// Whether this student currently has a hand up.
  bool _handRaised = false;
  bool get handRaised => _handRaised;

  /// Raise or lower this student's hand. The teacher sees it immediately.
  bool setHandRaised(bool raised) {
    if (_sessionId.isEmpty) return false;
    final sent = _client.send(SyncEvent(
      type: raised ? SyncEventType.handRaised : SyncEventType.handLowered,
      sessionId: _sessionId,
      participantName: _studentName,
    ));
    if (sent) {
      _handRaised = raised;
      notifyListeners();
    }
    return sent;
  }

  /// Tell the teacher which page this student is on. Reported, never applied:
  /// a student browsing ahead does not drag the class with them.
  void reportPage(int page) {
    if (_sessionId.isEmpty) return;
    _client.send(SyncEvent(
      type: SyncEventType.studentPageChanged,
      sessionId: _sessionId,
      participantName: _studentName,
      page: page,
    ));
  }

  Future<void> leave() async {
    await _client.disconnect();
    _bound = false;
    _link = LinkState.idle;
    _host = '';
    _sessionId = '';
    _snapshot = null;
    _hasDocument = false;
    _syncPaused = false;
    _handRaised = false;
    _error = null;
    await _eventSub?.cancel();
    _eventSub = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _stateSub?.cancel();
    _client.dispose();
    super.dispose();
  }
}
