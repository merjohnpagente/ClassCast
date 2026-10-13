import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/doc_types.dart';
import '../models/shared_document.dart';

/// Picks files and classifies them. Office files are preserved as-is and
/// flagged [DocStatus.needsConversion] — conversion happens on a compatible
/// laptop host (see `server/`), never silently on-device.
class DocumentService {
  static const _uuid = Uuid();

  static List<String> get allowedExtensions => SupportedFiles.all;

  Future<SharedDocument?> pickSingle() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );
      if (file == null) return null;
      return _toDoc(file);
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
      return Future.wait(files.map(_toDoc));
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
    return SharedDocument(
      id: 'doc-${_uuid.v4().substring(0, 8)}',
      name: base,
      extension: ext,
      kind: kind,
      sizeBytes: size,
      lastModified: DateTime.now(),
      status: SupportedFiles.initialStatus(kind),
      localPath: f.path,
    );
  }

  /// Short, honest guidance shown on the Share screen for Office files.
  static String? conversionNotice(SharedDocument doc) {
    switch (doc.status) {
      case DocStatus.needsConversion:
        return 'This ${_label(doc.kind)} file needs conversion to PDF on '
            'a compatible laptop host before presenting. The original file '
            'is preserved.';
      case DocStatus.converting:
        return 'Converting to PDF on the host… students will see it when ready.';
      case DocStatus.conversionFailed:
        return 'Conversion failed on this host. Try a laptop with LibreOffice '
            'installed, or share a PDF instead.';
      case DocStatus.unsupported:
        return 'This format is not supported. Use PDF, PPT, DOC, XLS, JPG, '
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
