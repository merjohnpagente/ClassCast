import 'dart:io';
import 'dart:typed_data';

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