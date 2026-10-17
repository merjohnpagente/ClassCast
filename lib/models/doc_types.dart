/// Supported document types in ClassCast Offline.
enum DocKind { pdf, powerpoint, word, excel, image, text, video, unknown }

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

  /// Video, for a recorded lesson rather than a deck. Played with the teacher
  /// driving: the class follows one playback position, and a video is the one
  /// shared document where being half a second out is actually visible.
  static const video = ['mp4', 'm4v', 'mov', 'webm', '3gp'];

  /// Office formats that are zip containers, opened by the app itself.
  static const modernOffice = ['pptx', 'docx', 'xlsx'];

  /// Office 97-2003 binary formats (OLE compound files, not zips). They can
  /// still be picked so the teacher gets a clear message, but they cannot be
  /// rendered on any device.
  static const legacyOffice = ['ppt', 'doc', 'xls'];

  static const all = [
    ...pdf,
    ...powerpoint,
    ...word,
    ...excel,
    ...image,
    ...text,
    ...video,
  ];

  static String normalize(String extension) =>
      extension.toLowerCase().replaceAll('.', '').trim();

  static DocKind kindOf(String extension) {
    final ext = normalize(extension);
    if (pdf.contains(ext)) return DocKind.pdf;
    if (powerpoint.contains(ext)) return DocKind.powerpoint;
    if (word.contains(ext)) return DocKind.word;
    if (excel.contains(ext)) return DocKind.excel;
    if (image.contains(ext)) return DocKind.image;
    if (text.contains(ext)) return DocKind.text;
    if (video.contains(ext)) return DocKind.video;
    return DocKind.unknown;
  }

  static DocStatus initialStatus(DocKind kind) {
    switch (kind) {
      case DocKind.pdf:
      case DocKind.image:
      case DocKind.text:
      case DocKind.powerpoint:
      case DocKind.word:
      case DocKind.excel:
      case DocKind.video:
        // Modern Office files are opened by the app itself, so they are ready
        // to present as soon as they are picked.
        return DocStatus.ready;
      case DocKind.unknown:
        return DocStatus.unsupported;
    }
  }

  /// True when the app renders this file on the device, with no laptop and no
  /// conversion step.
  static bool rendersOnDevice(String extension) =>
      modernOffice.contains(normalize(extension));

  static bool isLegacyOffice(String extension) =>
      legacyOffice.contains(normalize(extension));

  /// Status for a concrete file. Unlike [initialStatus] this sees the
  /// extension, so a legacy `.ppt` is correctly reported as unopenable.
  static DocStatus statusFor(String extension) {
    if (isLegacyOffice(extension)) return DocStatus.unsupported;
    return initialStatus(kindOf(extension));
  }
}
