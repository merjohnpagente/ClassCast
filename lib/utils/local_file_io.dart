import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Android / iOS / desktop: the real filesystem via `dart:io`.
///
/// This file is only compiled when `dart:io` exists (see `local_file.dart`).

/// Reads the whole file as bytes. Null when missing or unreadable.
Future<Uint8List?> localFileReadBytes(String path) async {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Reads the whole file as UTF-8 text. Null when missing or unreadable.
Future<String?> localFileReadString(String path) async {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    return await file.readAsString();
  } catch (_) {
    return null;
  }
}

/// Existence only. Cheap on purpose: the library prunes on startup, and
/// reading whole files to answer a yes/no question can cost hundreds of MB.
Future<bool> localFileExistsImpl(String path) async {
  if (path.isEmpty) return false;
  try {
    return await File(path).exists();
  } catch (_) {
    return false;
  }
}

/// Size in bytes, or null when missing or unreadable.
Future<int?> localFileSize(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    return await file.length();
  } catch (_) {
    return null;
  }
}

/// Persistent directory this app owns, for copies of documents the teacher
/// picked. `path_provider` resolves the per-platform documents directory;
/// null when it cannot, in which case callers keep the picked path.
Future<String?> localFilePersistentDir() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  } catch (_) {
    return null;
  }
}

/// Copies [sourcePath] into a directory this app owns and returns the new path.
///
/// A picked path points into the cache folder, which Android is free to delete
/// at any time — including halfway through a lesson, which would leave every
/// student with a 404. Returns null when there is nowhere to copy to, so the
/// caller can keep the original path rather than store nothing.
Future<String?> localFileCopyIntoAppStorage(
  String sourcePath,
  String fileName,
) async {
  final root = await localFilePersistentDir();
  if (root == null || sourcePath.isEmpty) return null;
  try {
    final source = File(sourcePath);
    if (!await source.exists()) return null;

    // Filename collisions are the normal case, not the exception: a teacher
    // picks "Quiz 1.pptx" in three consecutive lessons.
    final dir = Directory(p.join(root, 'documents'));
    if (!await dir.exists()) await dir.create(recursive: true);

    final safe = p.basename(fileName).isEmpty ? 'document' : p.basename(fileName);
    var target = p.join(dir.path, safe);
    if (await File(target).exists()) {
      final stem = p.withoutExtension(safe);
      final ext = p.extension(safe);
      var n = 2;
      while (await File(target).exists() && n < 500) {
        target = p.join(dir.path, '$stem ($n)$ext');
        n++;
      }
    }
    await source.copy(target);
    return target;
  } catch (_) {
    return null;
  }
}