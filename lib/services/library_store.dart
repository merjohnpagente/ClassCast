import 'dart:convert';

import '../models/shared_document.dart';
import '../utils/local_file_exists.dart';
import 'local_store.dart';

/// The teacher's document library, persisted on the device.
///
/// A file picker hands back a path in the app's cache folder, which Android is
/// free to delete. Without this, the library was empty after every restart and
/// "revive this session with its document" had nothing to revive — so the
/// library is written to the same SQLite store the sessions use, and entries
/// whose file has since vanished are dropped rather than shown as broken.
class LibraryStore {
  static const _key = 'classcast_library';

  Future<List<SharedDocument>> load() async {
    try {
      final raw = await localStore().read(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SharedDocument.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Adds or replaces a document, newest first, capped so the list stays a
  /// working set rather than an archive nobody prunes.
  Future<void> save(SharedDocument doc) async {
    if (doc.id.isEmpty) return;
    try {
      final current = await load();
      final updated = [
        doc,
        ...current.where((d) => d.id != doc.id),
      ].take(60).toList();
      await _write(updated);
    } catch (_) {/* best-effort cache */}
  }

  Future<void> saveAll(List<SharedDocument> docs) async {
    try {
      await _write(docs.take(60).toList());
    } catch (_) {/* ignore */}
  }

  Future<void> remove(String id) async {
    try {
      final current = await load();
      await _write(current.where((d) => d.id != id).toList());
    } catch (_) {/* ignore */}
  }

  /// Drops entries whose file is gone.
  ///
  /// Showing a library full of files that cannot be opened is worse than an
  /// empty one: the teacher picks a document and nothing happens.
  Future<List<SharedDocument>> pruneMissing() async {
    final current = await load();
    final kept = <SharedDocument>[];
    for (final doc in current) {
      final path = doc.localPath;
      if (path == null || path.isEmpty) continue;
      if (await localFileExists(path)) kept.add(doc);
    }
    if (kept.length != current.length) await _write(kept);
    return kept;
  }

  Future<void> _write(List<SharedDocument> docs) => localStore().write(
        _key,
        jsonEncode(docs.map((d) => d.toJson()).toList()),
      );
}