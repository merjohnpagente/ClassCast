import 'dart:typed_data';

/// Web: there is no filesystem, so a path picked by `file_picker` cannot be
/// reopened. Every read reports "unavailable" and the caller renders the
/// host URL instead — the honest behaviour rather than a silent blank frame.
///
/// This file is only compiled when `dart:io` is absent (see `local_file.dart`).

/// Always null: a browser cannot read a local path.
Future<Uint8List?> localFileReadBytes(String path) async => null;

/// Always null: a browser cannot read a local path.
Future<String?> localFileReadString(String path) async => null;