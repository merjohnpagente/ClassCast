/// Supported document types in ClassCast Offline.
enum DocKind { pdf, powerpoint, word, excel, image, text, unknown }

/// Lifecycle of a document selected for sharing.
enum DocStatus {
  /// Ready to present (PDF / image / text render directly).
  ready,

  /// Office file waiting for laptop-host conversion to PDF.
  needsConversion,

  /// Conversion is running on the host.
  converting,

  /// Host could not convert the file.
  conversionFailed,

  /// Format is not supported at all.
  unsupported,
}

/// Extension tables (lowercase, no dot).
class SupportedFiles {
  static const pdf = ['pdf'];
  static const powerpoint = ['ppt', 'pptx'];
  static const word = ['doc', 'docx'];
  static const excel = ['xls', 'xlsx'];
  static const image = ['jpg', 'jpeg', 'png'];
  static const text = ['txt'];

  static const all = [
    ...pdf,
    ...powerpoint,
    ...word,
    ...excel,
    ...image,
    ...text,
  ];

  static DocKind kindOf(String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    if (pdf.contains(ext)) return DocKind.pdf;
    if (powerpoint.contains(ext)) return DocKind.powerpoint;
    if (word.contains(ext)) return DocKind.word;
    if (excel.contains(ext)) return DocKind.excel;
    if (image.contains(ext)) return DocKind.image;
    if (text.contains(ext)) return DocKind.text;
    return DocKind.unknown;
  }

  static DocStatus initialStatus(DocKind kind) {
    switch (kind) {
      case DocKind.pdf:
      case DocKind.image:
      case DocKind.text:
        return DocStatus.ready;
      case DocKind.powerpoint:
      case DocKind.word:
      case DocKind.excel:
        // Office files need laptop-host conversion before presenting.
        return DocStatus.needsConversion;
      case DocKind.unknown:
        return DocStatus.unsupported;
    }
  }
}
