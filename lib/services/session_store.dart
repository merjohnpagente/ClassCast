import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/classroom_session.dart';

/// Local persistence for session info (no cloud).
class SessionStore {
  static const _recentKey = 'classcast_recent_sessions';
  static const _lastRoleKey = 'classcast_last_role';
  static const _studentNameKey = 'classcast_student_name';

  Future<List<ClassroomSession>> loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recentKey);
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
      final prefs = await SharedPreferences.getInstance();
      final current = await loadRecent();
      final updated = [
        session,
        ...current.where((s) => s.id != session.id),
      ].take(10).toList();
      await prefs.setString(
        _recentKey,
        jsonEncode(updated.map((s) => s.toJson()).toList()),
      );
    } catch (_) {/* offline cache is best-effort */}
  }

  Future<void> removeSession(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await loadRecent();
      final updated = current.where((s) => s.id != id).toList();
      await prefs.setString(
        _recentKey,
        jsonEncode(updated.map((s) => s.toJson()).toList()),
      );
    } catch (_) {/* ignore */}
  }

  Future<void> saveLastRole(String role) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRoleKey, role);
    } catch (_) {/* ignore */}
  }

  Future<String?> loadLastRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastRoleKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStudentName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_studentNameKey, name);
    } catch (_) {/* ignore */}
  }

  Future<String?> loadStudentName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_studentNameKey);
    } catch (_) {
      return null;
    }
  }
}
