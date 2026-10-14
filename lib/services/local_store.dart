import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Durable key/value storage for offline classroom data.
///
/// Android/iOS use **SQLite** (sqflite) so session history survives app
/// restarts and upgrades. Web/desktop fall back to SharedPreferences,
/// where SQLite is not available in a browser.
///
/// Tests inject their own implementation via [setLocalStoreOverride].
abstract class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// SQLite-backed store (Android / iOS).
class SqliteLocalStore implements LocalStore {
  static const _dbName = 'classcast.db';
  static const _table = 'app_store';

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get _instance {
    if (_db != null) return Future.value(_db);
    return _opening ??= _open().then((db) {
      _db = db;
      return db;
    });
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, _dbName),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_table (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
      // Upgrades are additive; nothing destructive here yet.
      onUpgrade: (db, oldV, newV) async {},
    );
  }

  @override
  Future<String?> read(String key) async {
    final db = await _instance;
    final rows = await db.query(_table,
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  @override
  Future<void> write(String key, String value) async {
    final db = await _instance;
    await db.insert(
      _table,
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String key) async {
    final db = await _instance;
    await db.delete(_table, where: 'key = ?', whereArgs: [key]);
  }

  @override
  Future<Map<String, String>> readAll() async {
    final db = await _instance;
    final rows = await db.query(_table);
    return {
      for (final r in rows) r['key'] as String: r['value'] as String
    };
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }
}

/// SharedPreferences-backed store (web, desktop, tests).
class PrefsLocalStore implements LocalStore {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _prefs).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await _prefs).setString(key, value);

  @override
  Future<void> delete(String key) async => (await _prefs).remove(key);

  @override
  Future<Map<String, String>> readAll() async {
    final p = await _prefs;
    return {
      for (final k in p.getKeys())
        if (p.getString(k) != null) k: p.getString(k)!,
    };
  }
}

LocalStore? _override;

/// Swap the store implementation (used by tests).
void setLocalStoreOverride(LocalStore? store) => _override = store;

/// SQLite where supported, SharedPreferences elsewhere.
LocalStore createLocalStore() {
  final o = _override;
  if (o != null) return o;
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return SqliteLocalStore();
  }
  return PrefsLocalStore();
}

/// Shared instance so every [SessionStore] hits the same database.
LocalStore? _shared;
LocalStore localStore() => _shared ??= createLocalStore();