import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/classroom_session.dart';
import '../models/sync_event.dart';
import '../services/classcast_client.dart';
import '../services/document_download.dart';
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

  /// Join flow: validate -> find the address that has this session -> subscribe.
  ///
  /// Returns true only when one of the addresses in the joining code hands back
  /// this session's snapshot, so the "Joined classroom" the caller shows is
  /// never a lie about a session the app could not read.
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

    // One address is not proof the classroom is reachable, and an answer is not
    // proof it is *this* classroom. The teacher's phone can hold several
    // addresses — the hotspot they serve, the Wi-Fi or hotspot they joined,
    // and the code carries all of them — and on a shared network something
    // else may well answer on one. So a candidate has to hand back this
    // session's own snapshot before it is believed; a bare ping used to be
    // enough, and a wrong neighbour's answer ended the join there.
    ClassroomSession? snapshot;
    final candidates = <String>[parsed.host, ...parsed.alts];
    for (var i = 0; i < candidates.length; i++) {
      final host = candidates[i].trim();
      if (host.isEmpty) continue;
      // The first address is the likely one and gets the full wait; the rest
      // are fallbacks, and a student staring at a spinner does not need to sit
      // through the whole timeout on each of them.
      final wait =
          i == 0 ? const Duration(seconds: 3) : const Duration(seconds: 2);
      if (!await NetworkService.probeHost(
          host: host, port: _port, timeout: wait)) {
        continue;
      }
      final snap = await _client.fetchSnapshot(
          host: host, port: _port, sessionId: _sessionId, timeout: wait);
      if (snap != null) {
        _host = host;
        snapshot = snap;
        break;
      }
    }
    if (snapshot == null) {
      _link = LinkState.offline;
      // This phone is the only one that can actually see the block: its
      // packets to the teacher either arrive or they do not. Name the likely
      // cause instead of sending the student to re-check an address the QR
      // filled in correctly.
      _error = 'Could not reach the teacher. On school or guest Wi-Fi, '
          'phones often cannot see each other — ask the teacher to switch on '
          'a hotspot, then scan the new QR code.';
      notifyListeners();
      return false;
    }

    _client.subscribe(
        host: _host,
        port: _port,
        sessionId: _sessionId,
        name: _studentName,
        device: device);
    // Bind before the snapshot is looked at, not inside the branch below.
    //
    // The events stream is a plain broadcast controller with no buffering, so
    // the host's opening `session_state` greeting — which arrives the moment
    // the socket opens — was being dropped on the floor: nothing was listening
    // yet. And with a null snapshot every later frame hit the
    // `if (base == null) return` in the handler, so the student could never be
    // brought back without leaving and rejoining. Listening unconditionally
    // is what lets a recovered session populate itself.
    bind();
    _snapshot = _withReachableUrl(snapshot);
    _syncPaused = snapshot.syncPaused;
    _hasDocument = snapshot.documentId != null;
    // Only a snapshot proves the host is answering. Saying "live" when the
    // fetch failed showed a green chip over a session that never connected;
    // the client sets live itself on the first socket frame from here.
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
          if (base == null) {
            // Recover rather than drop. The first snapshot fetch failed but the
            // socket is open and the host is talking, so the broadcast is the
            // only thing this student will ever get. Returning here is what left
            // them on "Joining Session…" with a green chip and no way out but
            // leaving and rejoining.
            _snapshot = ClassroomSession(
              id: _sessionId,
              name: _sessionId,
              hostIp: _host,
              port: _port,
              createdAt: DateTime.now(),
              isActive: true,
              documentId: event.documentId,
              documentName: event.documentName,
              documentUrl: event.documentUrl,
              page: event.page ?? 1,
              totalPages: event.totalPages ?? 0,
              syncPaused: event.syncPaused ?? false,
            );
          } else {
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
              // A new document has no playback to follow, whatever the last
              // one was doing.
              videoPositionMs: event.videoPositionMs ?? 0,
              videoPlaying: event.videoPlaying ?? false,
              videoDurationMs: event.videoDurationMs ?? 0,
            );
          }
          if (event.documentId != null) _hasDocument = true;
          // Point the file at the address this phone actually reached the
          // classroom on, before anything reads it.
          _snapshot = _withReachableUrl(_snapshot!);
          _syncPaused = _snapshot!.syncPaused;
          // Following the class again is normal teaching, so the hold is over.
          if (event.page != null) _takenOver = false;
          // A frame arriving at all is proof the host is talking, which is the
          // one thing the failed fetch could not tell us.
          if (_link != LinkState.ended) {
            _link = LinkState.live;
            _error = null;
          }
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
        case SyncEventType.videoChanged:
          // The teacher moved the video. Nothing to do here beyond letting the
          // snapshot carry it: the player watches these three values and puts
          // itself in the right place.
          final base = _snapshot;
          if (base == null) return;
          _snapshot = base.copyWith(
            videoPositionMs: event.videoPositionMs ?? base.videoPositionMs,
            videoPlaying: event.videoPlaying ?? base.videoPlaying,
            videoDurationMs: event.videoDurationMs ?? base.videoDurationMs,
          );
          notifyListeners();
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
        case SyncEventType.heartbeat:
          // Heartbeats go student-to-host; the host never sends one back.
          break;
      }
    });
  }

  /// True while the teacher holds this screen to the class page. Cleared as
  /// soon as the class page moves, because then following it is the point.
  bool _takenOver = false;
  bool get takenOver => _takenOver;

  /// The snapshot with its document URL aimed at an address this phone can
  /// actually use. Returns the same instance when there is nothing to change.
  ClassroomSession _withReachableUrl(ClassroomSession session) {
    final url = _reachableUrl(session.documentUrl ?? '');
    if (url == session.documentUrl) return session;
    return session.copyWith(documentUrl: () => url);
  }

  /// The host builds the document URL from the address *it* is advertising,
  /// which is not always the address this phone reached the classroom on: a
  /// teacher on the classroom Wi-Fi and serving a hotspot has both, and the
  /// student who joined on one of them may not be able to open the other.
  ///
  /// Whatever answered a moment ago can serve the file, so the host part of
  /// the URL becomes that address. The path and the token stay the host's —
  /// they are what makes the download allowed at all.
  String _reachableUrl(String url) {
    if (url.isEmpty || _host.isEmpty) return url;
    final parsed = Uri.tryParse(url);
    if (parsed == null) return url;
    // Root-relative (`/files/...`), which is what a host with no advertised
    // address hands out. It has no scheme to replace, so it is completed here.
    if (!parsed.hasScheme) {
      final query = parsed.hasQuery ? '?${parsed.query}' : '';
      return 'http://$_host:$_port${parsed.path}$query';
    }
    if (parsed.host == _host && parsed.port == _port) return url;
    return parsed.replace(host: _host, port: _port).toString();
  }

  /// Whether this student may turn pages right now.
  ///
  /// Turned off while taken over: that is what "take control" means, and
  /// letting the student keep turning pages would make it a no-op.
  bool get canNavigate =>
      (_snapshot?.allowStudentNav ?? false) && !_takenOver;

  /// Whether this student currently has a hand up.
  bool _handRaised = false;
  bool get handRaised => _handRaised;

  /// Playback of a shared video, in milliseconds from its start, and whether
  /// the teacher has it running.
  ///
  /// Mirrors of the teacher's own position, so a class of thirty phones is
  /// watching the same moment of the same recording rather than thirty copies
  /// of it that drifted apart.
  int get videoPositionMs => _snapshot?.videoPositionMs ?? 0;
  bool get videoPlaying => _snapshot?.videoPlaying ?? false;
  int get videoDurationMs => _snapshot?.videoDurationMs ?? 0;

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

  /// Fetch the teacher's shared file off the local network and save it with
  /// the platform's own save dialog. Never throws; the result carries a
  /// sentence for the student.
  Future<DocumentDownloadResult> downloadDocument() async {
    final doc = _snapshot;
    final url = _reachableUrl(doc?.documentUrl ?? '');
    final name = doc?.documentName ?? '';
    if (url.isEmpty || name.isEmpty) {
      return const DocumentDownloadResult(
          false, 'No file is shared by the teacher yet.');
    }
    return DocumentDownloader.download(url: url, fileName: name);
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
    // Also cleared: canNavigate is `allowStudentNav && !_takenOver`, and this
    // was not among the resets, so a student the teacher had ever taken over
    // could not turn a page again for the rest of the app's life — including
    // in the next class, which allows it.
    _takenOver = false;
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
