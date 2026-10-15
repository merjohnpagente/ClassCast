import 'dart:io';

import 'package:classcast_offline/models/classroom_session.dart';
import 'package:classcast_offline/models/doc_types.dart';
import 'package:classcast_offline/models/shared_document.dart';
import 'package:classcast_offline/services/library_store.dart';
import 'package:classcast_offline/services/local_store.dart';
import 'package:classcast_offline/services/session_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tiny in-memory [LocalStore], so these tests exercise the real stores
/// without SQLite (which is not available in the widget-test environment).
class _MemoryStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  late _MemoryStore store;

  setUp(() {
    store = _MemoryStore();
    setLocalStoreOverride(store);
  });
  // (The override above also drops the cached shared store, so each test
  // really does start on a clean database.)

  tearDown(() => setLocalStoreOverride(null));

  group('SessionStore', () {
    test('keeps sessions across a reload, newest first', () async {
      final sessions = SessionStore();
      await sessions.saveSession(ClassroomSession(
        id: 'CLASS-AAA',
        name: 'Physics',
        createdAt: DateTime(2026, 3, 1, 9),
      ));
      await sessions.saveSession(ClassroomSession(
        id: 'CLASS-BBB',
        name: 'Biology',
        createdAt: DateTime(2026, 3, 2, 9),
      ));

      final loaded = await sessions.loadRecent();
      expect(loaded.map((s) => s.id), ['CLASS-BBB', 'CLASS-AAA']);
      expect(loaded.first.name, 'Biology');
    });

    test('saving the same id updates instead of duplicating', () async {
      final sessions = SessionStore();
      await sessions.saveSession(ClassroomSession(
        id: 'CLASS-AAA',
        name: 'Old name',
        createdAt: DateTime(2026, 3, 1),
      ));
      await sessions.saveSession(ClassroomSession(
        id: 'CLASS-AAA',
        name: 'New name',
        subject: 'Physics',
        createdAt: DateTime(2026, 3, 1),
      ));

      final loaded = await sessions.loadRecent();
      expect(loaded.length, 1);
      expect(loaded.single.name, 'New name');
      expect(loaded.single.subject, 'Physics');
    });

    test('removeSession drops only that session', () async {
      final sessions = SessionStore();
      await sessions.saveSession(ClassroomSession(
          id: 'CLASS-AAA', name: 'A', createdAt: DateTime(2026, 3, 1)));
      await sessions.saveSession(ClassroomSession(
          id: 'CLASS-BBB', name: 'B', createdAt: DateTime(2026, 3, 2)));

      await sessions.removeSession('CLASS-AAA');
      final loaded = await sessions.loadRecent();
      expect(loaded.map((s) => s.id), ['CLASS-BBB']);
    });
  });

  group('LibraryStore', () {
    SharedDocument doc(String id, String name) => SharedDocument(
          id: id,
          name: name,
          extension: 'pptx',
          kind: DocKind.powerpoint,
          status: DocStatus.ready,
          pageCount: 12,
        );

    test('restores documents after a restart', () async {
      final library = LibraryStore();
      await library.save(doc('doc-1', 'Lesson'));
      await library.save(doc('doc-2', 'Review'));

      final loaded = await library.load();
      expect(loaded.map((d) => d.name), ['Review', 'Lesson']);
      expect(loaded.first.pageCount, 12);
    });

    test('a re-saved document replaces the old entry', () async {
      final library = LibraryStore();
      await library.save(doc('doc-1', 'Lesson'));
      await library.save(doc('doc-1', 'Lesson v2'));

      final loaded = await library.load();
      expect(loaded.length, 1);
      expect(loaded.single.name, 'Lesson v2');
    });

    test('remove drops the document', () async {
      final library = LibraryStore();
      await library.save(doc('doc-1', 'Lesson'));
      await library.save(doc('doc-2', 'Review'));
      await library.remove('doc-1');

      final loaded = await library.load();
      expect(loaded.map((d) => d.id), ['doc-2']);
    });

    test('a stored path survives a restart', () async {
      // This is the bug the library had: toJson never wrote localPath, so after
      // a restart every entry read back with no path and pruneMissing deleted
      // the whole library on the next launch.
      final library = LibraryStore();
      await library.save(SharedDocument(
        id: 'doc-1',
        name: 'Lesson',
        extension: 'pdf',
        kind: DocKind.pdf,
        localPath: '/storage/documents/Lesson.pdf',
      ));

      final restored = await library.load();
      expect(restored.single.localPath, '/storage/documents/Lesson.pdf');
    });

    test('entries whose file has vanished are pruned, real ones are kept',
        () async {
      final library = LibraryStore();
      final present = _tempFile('present.pdf');
      addTearDown(() => present.deleteSync());

      await library.save(SharedDocument(
        id: 'doc-1',
        name: 'Gone',
        extension: 'pdf',
        kind: DocKind.pdf,
        localPath: '/definitely/not/here.pdf',
      ));
      await library.save(SharedDocument(
        id: 'doc-2',
        name: 'Present',
        extension: 'pdf',
        kind: DocKind.pdf,
        localPath: present.path,
      ));
      await library.save(SharedDocument(
        id: 'doc-3',
        name: 'No path yet',
        extension: 'docx',
        kind: DocKind.word,
      ));

      final kept = await library.pruneMissing();
      // Newest first, the way the library stores them.
      expect(kept.map((d) => d.id), ['doc-3', 'doc-2']);
      expect(await library.load(), hasLength(2));
    });

    test('saving several files keeps the ones already stored', () async {
      // saveAll used to overwrite the library with just the new batch, so
      // picking three files in one go erased everything before them.
      final library = LibraryStore();
      await library.save(SharedDocument(
        id: 'doc-old',
        name: 'Old',
        extension: 'pdf',
        kind: DocKind.pdf,
      ));
      await library.saveAll([
        SharedDocument(
            id: 'doc-a', name: 'A', extension: 'pdf', kind: DocKind.pdf),
        SharedDocument(
            id: 'doc-b', name: 'B', extension: 'pdf', kind: DocKind.pdf),
      ]);

      final ids = (await library.load()).map((d) => d.id).toSet();
      expect(ids, {'doc-old', 'doc-a', 'doc-b'});
    });

    test('an unreadable store is reported, not silently emptied', () async {
      final library = LibraryStore();
      await store.write('classcast_library', '{not json');

      expect(library.load, throwsA(isA<LibraryReadException>()));
    });
  });
}

/// A real file on disk, so "is it still there" is answered by the filesystem
/// rather than by a hardcoded false.
File _tempFile(String name) {
  final dir = Directory.systemTemp.createTempSync('classcast_test');
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  file.writeAsStringSync('%PDF-1.4');
  return file;
}