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
}