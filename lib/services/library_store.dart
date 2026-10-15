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
    } catch (e) {
      // An unreadable row must not masquerade as "you have no documents":
      // the teacher re-picks files they already have, and this time they see
      // an error instead of an empty list that looks deliberate.
      throw LibraryReadException(e);
    }
  }

  /// Adds or replaces a document, newest first, capped so the list stays a
  /// working set rather than an archive nobody prunes.
  Future<void> save(SharedDocument doc) => saveAll([doc]);

  /// Adds every document in [docs], keeping the ones already stored.
  ///
  /// This used to overwrite the whole library with just the new batch, so
  /// picking three files erased sixty.
  Future<void> saveAll(List<SharedDocument> docs) async {
    final incoming =
        docs.where((d) => d.id.isNotEmpty).toList(growable: false);
    if (incoming.isEmpty) return;
    final current = await load();
    final ids = incoming.map((d) => d.id).toSet();
    final merged = [
      ...incoming,
      ...current.where((d) => !ids.contains(d.id)),
    ].take(60).toList();
    await _write(merged);
  }

  Future<void> remove(String id) async {
    final current = await load();
    await _write(current.where((d) => d.id != id).toList());
  }

  /// Drops entries whose file is gone.
  ///
  /// Showing a library full of files that cannot be opened is worse than an
  /// empty one: the teacher picks a document and nothing happens. An entry with
  /// no path at all is kept, not deleted: it is a record of a document the
  /// teacher may still have elsewhere, and dropping it is what emptied the
  /// library on every single launch.
  Future<List<SharedDocument>> pruneMissing() async {
    final current = await load();
    final kept = <SharedDocument>[];
    for (final doc in current) {
      final path = doc.localPath;
      if (path == null || path.isEmpty) {
        kept.add(doc);
        continue;
      }
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

/// The stored library could not be read at all, so the teacher is told instead
/// of being shown an empty library that looks like a deliberate answer.
class LibraryReadException implements Exception {
  final Object cause;

  const LibraryReadException(this.cause);

  @override
  String toString() => 'The saved library could not be read: $cause';
}