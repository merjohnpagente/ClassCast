import 'package:file_picker/file_picker.dart';
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
    } catch (_) {
      return null;
    }
  }

  Future<List<SharedDocument>> pickMultiple() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      return await Future.wait(files.map(_toDoc));
    } catch (_) {
      return [];
    }
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
    final path = f.path;
    final status = SupportedFiles.statusFor(ext);

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
      pageCount: SupportedFiles.rendersOnDevice(ext) && size <= _maxCountBytes
          ? await _countPages(ext, path)
          : 0,
      localPath: path,
    );
  }

  /// Slides / pages / printed sheet pages of an Office file. 0 when it cannot
  /// be read, which the UI already treats as "unknown total".
  static Future<int> _countPages(String extension, String? path) async {
    if (path == null || path.isEmpty) return 0;
    final bytes = await localFileReadBytes(path);
    if (bytes == null || bytes.isEmpty) return 0;
    final parsed = OoxmlLoader.parseBytes(extension: extension, bytes: bytes);
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
