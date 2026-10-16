import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/classroom_session.dart';
import '../models/participant.dart';
import '../models/shared_document.dart';
import '../models/sync_event.dart';
import '../services/host/classcast_host.dart';
import '../services/network_service.dart';
import '../services/ooxml/ooxml_document.dart';
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
        teacherKey: s.teacherKey,
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

  void _clearHostStatus() => _host.clearLastStatus();

  /// True when this device is serving the classroom itself.
  ///
  /// Without a listener there is nothing for a student to join, no matter how
  /// good the Wi-Fi is — so the teacher UI states this plainly.
  bool get hostingLocally => ClasscastHost.instance.running;

  /// Address students can reach, empty until the host is up.
  String get hostAddress => ClasscastHost.instance.joinUrl;

  ClassroomSession? _active;
  ClassroomSession? get active => _active;

  List<ClassroomSession> _recent = [];
  List<ClassroomSession> get recent => List.unmodifiable(_recent);

  List<Participant> _participants = [];
  List<Participant> get participants => List.unmodifiable(_participants);

  /// Students who have a hand up, newest last. A raised hand that the teacher
  /// never sees is a broken feature, so this is surfaced in the roster and as
  /// a badge on the presentation screen.
  final Map<String, String> _raisedHands = {};
  Map<String, String> get raisedHands => Map.unmodifiable(_raisedHands);

  /// Page each student is currently on, so the teacher can see that someone
  /// browsed ahead or fell behind without taking the class page from them.
  final Map<String, int> _studentPages = {};
  Map<String, int> get studentPages => Map.unmodifiable(_studentPages);

  /// Clear a raised hand (the student answered, or it was dismissed).
  void lowerHand(String participantId) {
    if (_raisedHands.remove(participantId) == null) return;
    notifyListeners();
  }

  bool _loaded = false;
  bool get isLoaded => _loaded;

  int get connectedCount => _participants
      .where((p) => p.status == Presence.connected)
      .length;

  /// Load sessions saved on this device (SQLite). No sample data.
  ///
  /// The live roster is deliberately left alone: this refreshes what is stored
  /// on disk, and clearing `_participants` here made every connected student
  /// vanish from the teacher's screen for the rest of the lesson.
  Future<void> load() async {
    _recent = await _store.loadRecent();
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

    // Bring up the classroom server on this device *before* announcing the
    // session. A session nothing is listening for cannot be joined, which is
    // exactly what happened when the app only posted to a host that did not
    // exist yet.
    await _startHost(session);

    // Register the session on the host so students can join it, and listen
    // for the roster events it broadcasts back.
    //
    // Awaited, and its result acted on: this used to be fire-and-forget, so a
    // host that refused the session left the teacher staring at a QR code that
    // no student could ever join, with nothing to indicate why.
    final registered = await _host.startSession(session);
    if (registered) {
      _hostReachable = true;
      _hostError = null;
    } else {
      _hostReachable = false;
      _hostError = 'Students cannot reach this device. The classroom server '
          'did not accept the session.';
      notifyListeners();
    }
    _openHostEvents(session);
    return session;
  }

  /// Whether the last control call to the classroom server succeeded.
  bool _hostReachable = true;
  String? _hostError;

  /// True once the session has been registered and control calls work.
  bool get classroomReady => _hostReachable;

  /// Why the classroom server could not be reached, if that is the case.
  String? get classroomError => _hostError;

  /// Starts the in-app host, restarting it if the port changed.
  Future<void> _startHost(ClassroomSession session) async {
    final host = ClasscastHost.instance;
    if (host.running && host.port == session.port) {
      if (session.hostIp.isNotEmpty) {
        // Refresh the advertised address for a new network.
        await host.start(
          port: session.port,
          advertisedIp: session.hostIp,
        );
      }
      return;
    }
    if (host.running) await host.stop();
    final started = await host.start(
      port: session.port,
      advertisedIp: session.hostIp,
    );
    if (!started) {
      // The UI says so; the teacher can pick another port or use a laptop host.
      _safeNotify();
    }
  }

  Future<void> endSession() async {
    if (_active == null) return;
    final ending = _active!;
    _closeHostEvents();
    // Let the "session ended" frame actually leave before the server goes
    // away. Firing it unawaited and stopping the host underneath it made a
    // normal, successful End paint a red "host offline" chip.
    try {
      await _host.endSession(ending);
    } catch (_) {/* the server may already be gone; that is not an error */}
    _clearHostStatus();
    // Stop serving: the classroom is over, and leaving a listener running
    // would keep the camera-era battery drain going for no reason.
    await ClasscastHost.instance.stop();
    // Parsed decks hold their images as raw bytes. Six of them stayed resident
    // for the rest of the day because nothing ever released the cache.
    OoxmlLoader.instance.clear();
    final ended = ending.copyWith(isActive: false);
    await _store.saveSession(ended);
    _recent = await _store.loadRecent();
    _active = null;
    _participants = [];
    notifyListeners();
  }

  void setNetwork({required String hostIp, required int port}) {
    if (_active == null) return;
    final active = _active!;
    final changed = active.hostIp != hostIp || active.port != port;
    _active = active.copyWith(hostIp: hostIp, port: port);
    notifyListeners();
    if (!changed) return;
    // A different address means a different network. Re-announce the session
    // there, or the QR and the roster keep pointing at an address that no
    // longer exists — which is what happened after switching from Wi-Fi to a
    // hotspot mid-lesson.
    unawaited(_host.startSession(_active!));
    _openHostEvents(_active!);
  }

  /// Re-reads this device's address and tells the host about it.
  ///
  /// Worth calling whenever the teacher is about to show a QR: turning the
  /// hotspot on after starting the session changes the address from the Wi-Fi
  /// one to the hotspot one, and nothing else notices.
  Future<bool> refreshNetwork() async {
    final active = _active;
    if (active == null) return false;
    final ip = await NetworkService().localIp();
    if (ip.isEmpty) return false;
    setNetwork(hostIp: ip, port: active.port);
    return true;
  }

  /// Shares [doc] with the class. Returns false when the host refused it, so
  /// the screen can say so instead of showing the class an empty page.
  Future<bool> shareDocument(SharedDocument doc, {int totalPages = 0}) async {
    final active = _active;
    if (active == null) return false;
    final pages = totalPages > 0 ? totalPages : doc.pageCount;
    // The host keys the file off its name, so it must match what is in the
    // shared directory exactly.
    final fileName =
        '${doc.name}${doc.extension.isEmpty ? '' : '.${doc.extension}'}';
    // Hand the host the file it must serve. Only the current document is ever
    // reachable, so the rest of the teacher's phone stays private.
    final path = doc.localPath;
    if (path != null && path.isNotEmpty) {
      ClasscastHost.instance.registerDocument(fileName, path);
    }
    _active = _active!.copyWith(
      documentId: () => doc.id,
      documentName: () => fileName,
      page: 1,
      totalPages: pages,
    );
    notifyListeners();
    return await _host.shareDocument(
      _active!,
      documentId: doc.id,
      documentName: fileName,
      totalPages: pages,
    );
  }

  void clearDocument() {
    if (_active == null) return;
    _active = _active!
        .copyWith(documentId: () => null, documentName: () => null);
    notifyListeners();
    // Stop serving the file locally as well, or a student who kept the URL
    // could still pull it after the teacher unshared it.
    ClasscastHost.instance.clearDocument();
    // Tell the host too, otherwise students keep rendering the old file.
    unawaited(_host.clearDocument(_active!));
  }

  /// Save an edited session (rename, subject, settings) and persist it, so the
  /// recent list shows the change and the change survives a restart.
  Future<void> updateSession(ClassroomSession updated) async {
    if (updated.id.isEmpty) return;
    if (_active?.id == updated.id) {
      _active = updated;
    }
    await _store.saveSession(updated);
    _recent = await _store.loadRecent();
    notifyListeners();
    // A live session also lives on the host: push the new name/settings there.
    if (_active?.id == updated.id) {
      unawaited(_host.startSession(_active!));
    }
  }

  /// Delete a session from the recent list (and end it if it was live).
  Future<void> deleteSession(String id) async {
    if (_active?.id == id) {
      await endSession();
    }
    await _store.removeSession(id);
    _recent = await _store.loadRecent();
    notifyListeners();
  }

  /// Bring an ended session back to life with the **same session id**, so a
  /// printed QR code or a saved session id works again. The roster and the
  /// page start fresh, and an optional document from the teacher's library is
  /// re-shared so the class continues where it left off.
  Future<ClassroomSession?> reviveSession(
    ClassroomSession old, {
    required String hostIp,
    required int port,
    SharedDocument? document,
  }) async {
    if (old.id.isEmpty) return null;
    if (_active != null) await endSession();
    final session = old.copyWith(
      hostIp: hostIp,
      port: port,
      isActive: true,
      createdAt: DateTime.now(),
      teacherKey: _uuid.v4().substring(0, 8),
      page: 1,
      syncPaused: false,
      documentId: () => null,
      documentName: () => null,
      documentUrl: () => null,
    );
    _active = session;
    await _store.saveSession(session);
    _recent = await _store.loadRecent();
    notifyListeners();
    await _startHost(session);
    unawaited(_host.startSession(session));
    _openHostEvents(session);
    if (document != null) {
      unawaited(shareDocument(document, totalPages: document.pageCount));
    }
    return session;
  }

  /// Publish the real page count of the shared document.
  ///
  /// The app only learns how many slides or pages a file has once it has been
  /// opened and parsed, which happens after `shareDocument`. Students need the
  /// total to enable their navigation, so it is pushed to the host as well.
  void setTotalPages(int totalPages) {
    if (_active == null || totalPages <= 0) return;
    if (_active!.documentId == null) return;
    if (_active!.totalPages == totalPages) return;
    _active = _active!.copyWith(totalPages: totalPages);
    notifyListeners();
    unawaited(_host.setPage(_active!, _active!.page, totalPages: totalPages));
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
    // The teacher sets the page, POSTs it, and the host broadcasts it straight
    // back to this same socket. Without this the echo arrived after the real
    // update and rebuilt the entire presentation screen a second time for a
    // page number that had not moved. It also fired whenever two controls were
    // pressed faster than the host could answer, in which case the older echo
    // arrived last and rewound the teacher.
    if (_active!.page == clamped) return clamped;
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

  /// Pull a wandering student back onto the class page. Omitting the id pulls
  /// the whole class back, which is what a teacher means by "take control".
  void takeControl({String? participantId}) {
    final active = _active;
    if (active == null) return;
    unawaited(_host.takeControl(active, participantId: participantId));
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
          _raisedHands.remove(event.participantId!);
          _studentPages.remove(event.participantId!);
        }
        break;
      case SyncEventType.handRaised:
        // The teacher raises and lowers hands locally too, so the host echoes
        // this straight back down the teacher's own socket. Notifying on an
        // unchanged map rebuilt the whole presentation screen for nothing.
        if (event.participantId != null) {
          final id = event.participantId!;
          final name = event.participantName ?? 'Student';
          if (_raisedHands[id] != name) {
            _raisedHands[id] = name;
            notifyListeners();
          }
        }
        break;
      case SyncEventType.handLowered:
        if (event.participantId != null &&
            _raisedHands.remove(event.participantId!) != null) {
          notifyListeners();
        }
        break;
      case SyncEventType.studentPageChanged:
        // A burst of these is the noisiest thing on the wire: every student
        // reports on every class page change, and each one used to rebuild the
        // teacher's entire screen including the document.
        if (event.participantId != null &&
            event.page != null &&
            _studentPages[event.participantId!] != event.page) {
          _studentPages[event.participantId!] = event.page!;
          notifyListeners();
        }
        break;
      case SyncEventType.join:
      case SyncEventType.sessionState:
      case SyncEventType.connectionStatus:
      case SyncEventType.takeControl:
        // The host answers the teacher's take-control with a page change on the
        // student's own socket only; the teacher's screen has nothing to do.
        break;
    }
  }

  void addParticipant(Participant p) {
    if (_participants.any((e) => e.id == p.id)) return;
    _participants = [..._participants, p];
    notifyListeners();
  }

  void removeParticipant(String id) {
    final before = _participants.length;
    _participants = _participants.where((p) => p.id != id).toList();
    // A leave for somebody who was never here changes nothing, and this is
    // called on every socket close on the host.
    if (_participants.length == before) return;
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
