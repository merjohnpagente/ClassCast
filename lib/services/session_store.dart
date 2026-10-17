import 'dart:convert';

import '../models/classroom_session.dart';
import 'local_store.dart';

/// Local persistence for session info. No cloud, no accounts.
///
/// Backed by SQLite on Android/iOS (see [local_store]) so recent
/// sessions and preferences survive restarts and app upgrades.
class SessionStore {
  static const _recentKey = 'classcast_recent_sessions';
  static const _lastRoleKey = 'classcast_last_role';
  static const _studentNameKey = 'classcast_student_name';
  static const _videoMutedKey = 'classcast_video_muted';
  static const _scrollViewKey = 'classcast_scroll_view';

  Future<List<ClassroomSession>> loadRecent() async {
    try {
      final raw = await localStore().read(_recentKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ClassroomSession.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSession(ClassroomSession session) async {
    try {
      final current = await loadRecent();
      final updated = [
        session,
        ...current.where((s) => s.id != session.id),
      ].take(10).toList();
      await localStore().write(
        _recentKey,
        jsonEncode(updated.map((s) => s.toJson()).toList()),
      );
    } catch (_) {/* local cache is best-effort */}
  }

  Future<void> removeSession(String id) async {
    try {
      final current = await loadRecent();
      final updated = current.where((s) => s.id != id).toList();
      await localStore().write(
        _recentKey,
        jsonEncode(updated.map((s) => s.toJson()).toList()),
      );
    } catch (_) {/* ignore */}
  }

  Future<void> saveLastRole(String role) async {
    try {
      await localStore().write(_lastRoleKey, role);
    } catch (_) {/* ignore */}
  }

  Future<String?> loadLastRole() async {
    try {
      return await localStore().read(_lastRoleKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStudentName(String name) async {
    try {
      await localStore().write(_studentNameKey, name);
    } catch (_) {/* ignore */}
  }

  Future<String?> loadStudentName() async {
    try {
      return await localStore().read(_studentNameKey);
    } catch (_) {
      return null;
    }
  }

  /// Whether this phone plays a shared video without sound.
  ///
  /// Saved, not just remembered: a student who muted because their phone is
  /// in a silent row of thirty has to make that choice again after every
  /// restart otherwise, and the default is *sound on*.
  Future<void> saveVideoMuted(bool muted) async {
    try {
      await localStore().write(_videoMutedKey, muted ? '1' : '0');
    } catch (_) {/* ignore */}
  }

  Future<bool> loadVideoMuted() async {
    try {
      return await localStore().read(_videoMutedKey) == '1';
    } catch (_) {
      return false;
    }
  }

  /// Whether this phone reads the shared document as one long scroll.
  ///
  /// Saved for the same reason the mute is: it is how this device likes to be
  /// taught, and asking again on every launch would be the app not believing
  /// the answer it was given.
  Future<void> saveScrollView(bool scroll) async {
    try {
      await localStore().write(_scrollViewKey, scroll ? '1' : '0');
    } catch (_) {/* ignore */}
  }

  Future<bool> loadScrollView() async {
    try {
      return await localStore().read(_scrollViewKey) == '1';
    } catch (_) {
      return false;
    }
  }
}
