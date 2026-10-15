import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/doc_types.dart';
import '../models/shared_document.dart';
import '../utils/local_file.dart';
import 'ooxml/ooxml_document.dart';

/// Picks files and classifies them.
///
/// Modern Office files (.pptx / .docx / .xlsx) are opened by the app itself, so
/// they are counted and marked ready here. Legacy binary Office files (.ppt /
/// .doc / .xls) are a different container that no device can render, and are
/// reported honestly instead of failing later on the presentation screen.
class DocumentService {
  static const _uuid = Uuid();

  /// Anything larger is not parsed at pick time; the viewer opens it lazily.
  static const int _maxCountBytes = 64 * 1024 * 1024;

  static List<String> get allowedExtensions => SupportedFiles.all;

  Future<SharedDocument?> pickSingle() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      if (file == null) return null;
      return await _toDoc(file);
    } on FilePickException catch (e) {
      // A plugin crash or a denied SAF prompt used to return null, which is
      // indistinguishable from the teacher cancelling: they tap Add and
      // nothing happens with no explanation.
      throw FilePickException(e.message);
    } catch (e) {
      throw FilePickException('The file could not be opened: $e');
    }
  }

  Future<List<SharedDocument>> pickMultiple() async {
    final List<PlatformFile> files;
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      files = picked ?? const [];
    } catch (e) {
      throw FilePickException('The files could not be opened: $e');
    }
    // One at a time, on purpose: Future.wait parsed N Office files at once and
    // several of them at once is what froze the UI on a real deck.
    final docs = <SharedDocument>[];
    for (final file in files) {
      docs.add(await _toDoc(file));
    }
    return docs;
  }

  Future<SharedDocument> _toDoc(PlatformFile f) async {
    final name = f.name;
    final dot = name.lastIndexOf('.');
    final base = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
    final kind = SupportedFiles.kindOf(ext);
    int size = 0;
    try {
      size = await f.xFile.length();
    } catch (_) {/* size is best-effort */}
    final status = SupportedFiles.statusFor(ext);

    // The picked path is a cache path. Copy first: by the time the teacher
    // opens this in tomorrow's lesson the cache entry may already be gone, and
    // a library entry pointing at nothing is the whole bug this fixes.
    final picked = f.path;
    final stored = picked == null || picked.isEmpty
        ? null
        : await localFileCopyIntoAppStorage(picked, name);
    final path = stored ?? picked;

    return SharedDocument(
      id: 'doc-${_uuid.v4().substring(0, 8)}',
      name: base,
      extension: ext,
      kind: kind,
      sizeBytes: size,
      lastModified: DateTime.now(),
      status: status,
      // Counting slides / pages / printed sheet pages up front lets the session
      // sync a real total instead of an unknown one.
      pageCount: SupportedFiles.rendersOnDevice(ext) &&
              path != null &&
              size <= _maxCountBytes
          ? await _countPages(ext, path)
          : 0,
      localPath: path,
    );
  }

  /// Slides / pages / printed sheet pages of an Office file. 0 when it cannot
  /// be read, which the UI already treats as "unknown total".
  ///
  /// Runs on a background isolate: inflating a 64 MB archive and parsing its
  /// XML on the UI thread is what made picking a deck feel like a freeze.
  static Future<int> _countPages(String extension, String? path) async {
    if (path == null || path.isEmpty) return 0;
    final bytes = await localFileReadBytes(path);
    if (bytes == null || bytes.isEmpty) return 0;
    try {
      return await compute(_pageCountIn, <String, Object?>{
        'extension': extension,
        'bytes': bytes,
      });
    } catch (_) {
      return 0;
    }
  }

  /// Runs in the background isolate. Returns the page count, 0 when unreadable.
  static int _pageCountIn(String? extension, Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return 0;
    final parsed =
        OoxmlLoader.parseBytes(extension: extension ?? '', bytes: bytes);
    return parsed?.pageCount ?? 0;
  }

  /// Short, honest guidance shown on the Share screen.
  static String? conversionNotice(SharedDocument doc) {
    switch (doc.status) {
      case DocStatus.needsConversion:
        return 'This ${_label(doc.kind)} file needs conversion to PDF on '
            'a compatible laptop host before presenting. The original file '
            'is preserved.';
      case DocStatus.converting:
        return 'Converting to PDF on the host… students will see it when ready.';
      case DocStatus.conversionFailed:
        return 'Could not read this file. Try re-saving it, or share a PDF.';
      case DocStatus.unsupported:
        if (SupportedFiles.isLegacyOffice(doc.extension)) {
          return 'Old Office 97-2003 .${doc.extension} files use a format no '
              'device can open directly. Open it once and "Save as" the newer '
              'format (or a PDF), then share that file.';
        }
        return 'This format is not supported. Use PDF, PPTX, DOCX, XLSX, JPG, '
            'PNG, or TXT.';
      case DocStatus.ready:
        return null;
    }
  }

  static String _label(DocKind kind) {
    switch (kind) {
      case DocKind.powerpoint:
        return 'PowerPoint';
      case DocKind.word:
        return 'Word';
      case DocKind.excel:
        return 'Excel';
      default:
        return 'Office';
    }
  }
}

/// Picking failed for a reason the teacher needs to hear. Cancelling is not an
/// error and returns null; this is everything else.
class FilePickException implements Exception {
  final String message;

  const FilePickException(this.message);

  @override
  String toString() => message;
}
