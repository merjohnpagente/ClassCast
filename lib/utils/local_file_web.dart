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

/// Always false: a browser has nothing on disk to check.
Future<bool> localFileExistsImpl(String path) async => false;

/// Always null: a browser has no file sizes.
Future<int?> localFileSize(String path) async => null;

/// Always null: there is nowhere on a web page to copy a document to.
Future<String?> localFilePersistentDir() async => null;

/// Always null: a browser cannot copy a local file anywhere. The viewer falls
/// back to the URL served by the teacher host.
///
/// [copyCeilingBytes] is accepted so this and the io version have one shape —
/// a signature that differs per platform is a mistake waiting to happen.
Future<String?> localFileCopyIntoAppStorage(
  String sourcePath,
  String fileName, {
  int copyCeilingBytes = 200 * 1024 * 1024,
}) async =>
    null;

/// A browser has no file handles, so this is always null.
Object? localFileHandle(String path) => null;
