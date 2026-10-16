import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/classroom_session.dart';
import 'sync_protocol.dart';

/// Teacher-side control client for the laptop host (`server/`).
///
/// Every call is authenticated with the session's teacher key and only ever
/// goes to the local network — there is no cloud endpoint anywhere.
///
/// Design rule: **the host is never allowed to block the teacher.** Local
/// state is updated first and the request is fired in the background; if the
/// host is unreachable the teacher keeps presenting and the UI shows an
/// honest "students not reached" hint instead of a fake Connected state.
class TeacherHostClient {
  static const timeout = Duration(seconds: 4);

  /// Result of the last control call, for the UI to surface.
  bool lastCallOk = true;
  String? lastError;

  /// Forget the outcome of the last call. Ending a session tears the host down
  /// on purpose, so the failure that follows is not something to show.
  void clearLastStatus() {
    lastCallOk = true;
    lastError = null;
  }

  /// Invoked after every completed call so the teacher UI can repaint its
  /// host-status chip.
  void Function()? onStatusChanged;

  /// Calls are serialised: `shareDocument` must never overtake
  /// `startSession`, or the host answers 403 because no session exists yet.
  Future<void> _chain = Future<void>.value();

  bool _usable(ClassroomSession s) => s.hostIp.isNotEmpty && s.isActive;

  Uri _uri(ClassroomSession s, String path) =>
      Uri(scheme: 'http', host: s.hostIp, port: s.port, path: path);

  /// Start (or update) the session on the host.
  Future<bool> startSession(ClassroomSession s) => _serial(() => _post(
        s,
        SyncProtocol.sessionApi,
        {
          'id': s.id,
          'name': s.name,
          'subject': s.subject,
          'allowAnonymous': s.allowAnonymous,
          'allowDownload': s.allowDownload,
          'allowStudentNav': s.allowStudentNav,
        },
      ));

  /// Move the class to [page]. [totalPages] is sent when the teacher app has
  /// just learned the real page count of a file it opened, so students get the
  /// correct total instead of an unknown one.
  Future<bool> setPage(ClassroomSession s, int page, {int? totalPages}) =>
      _serial(() => _post(s, SyncProtocol.pageApi, {
        'page': page,
        if (totalPages != null && totalPages > 0) 'totalPages': totalPages,
      }));

  Future<bool> shareDocument(
    ClassroomSession s, {
    required String documentId,
    required String documentName,
    required int totalPages,
  }) =>
      _serial(() => _post(s, SyncProtocol.documentApi, {
        'documentId': documentId,
        'documentName': documentName,
        'totalPages': totalPages,
      }));

  Future<bool> setPaused(ClassroomSession s, bool paused) =>
      _serial(() => _post(s, SyncProtocol.pauseApi, {'paused': paused}));

  /// Pull [participantId] back to the class page, or everyone when it is null.
  Future<bool> takeControl(ClassroomSession s, {String? participantId}) =>
      _serial(() => _post(s, SyncProtocol.takeControlApi, {
        if (participantId != null) 'participantId': participantId,
      }));

  Future<bool> endSession(ClassroomSession s) =>
      _serial(() => _post(s, SyncProtocol.endApi, const {}));

  /// Stop sharing the current document.
  Future<bool> clearDocument(ClassroomSession s) =>
      _serial(() => _post(s, SyncProtocol.documentApi, const {'clear': true}));

  /// Queue [op] behind any in-flight call, keeping the chain alive even when
  /// one call fails.
  Future<bool> _serial(Future<bool> Function() op) {
    final result = _chain.then((_) => op());
    _chain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<bool> _post(
    ClassroomSession s,
    String path,
    Map<String, dynamic> body,
  ) async {
    // No host address configured means the teacher is running standalone
    // (no laptop server). That is a legitimate mode, not an error — but it was
    // reporting success to the status listener *and* returning failure to the
    // caller from the same branch, so `hostReachable` read true while
    // `classroomReady` read false and the app bar could never agree on a
    // colour. A deliberate no-op reports as one thing: not called, not failed.
    if (!_usable(s)) {
      _status(null, null);
      return false;
    }
    try {
      final res = await http
          .post(
            _uri(s, path),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({...body, 'teacherKey': s.teacherKey}),
          )
          .timeout(timeout);
      final ok = res.statusCode == 200;
      _status(ok, ok ? null : 'Host returned ${res.statusCode}');
      return ok;
    } catch (_) {
      _status(false, 'Host unreachable at ${s.hostIp}:${s.port}');
      return false;
    }
  }

  /// [ok] is null when the call was not attempted — the standalone case — and
  /// is deliberately not reported as either success or failure.
  void _status(bool? ok, String? error) {
    if (ok == null) return;
    // Only when something actually changed. Every control call used to notify
    // unconditionally, so turning a page rebuilt the teacher's whole screen
    // twice: once for the change, once for the round trip that changed nothing.
    if (lastCallOk == ok && lastError == error) return;
    lastCallOk = ok;
    lastError = error;
    onStatusChanged?.call();
  }
}
