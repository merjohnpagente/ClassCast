import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

/// Outcome of a student download, with a sentence the UI can show as-is.
class DocumentDownloadResult {
  final bool ok;
  final String message;

  const DocumentDownloadResult(this.ok, this.message);
}

/// Fetches the teacher's shared file over the local network and saves it on
/// this device.
///
/// This is the student download path: the bytes travel straight from the
/// teacher's phone over the hotspot or classroom Wi-Fi — there is no cloud
/// step and no internet requirement — and the platform's own save dialog
/// (SAF on Android, the browser on web) puts the file where the student
/// wants it: Downloads, Documents, anywhere.
class DocumentDownloader {
  static const Duration _timeout = Duration(seconds: 30);

  /// One retry on purpose: the most common failure on a hotspot is a transfer
  /// that ended mid-flight, and asking again costs a second and actually
  /// fixes it.
  static const int _attempts = 2;

  /// The raw bytes of [url], or null when the host cannot serve them.
  ///
  /// Public so a test can prove the file really moves over HTTP from the
  /// teacher host, with nothing but the URL the session handed out.
  static Future<Uint8List?> fetch(String url, {int attempts = _attempts}) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(_timeout);
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          return res.bodyBytes;
        }
        // A refused or missing file will not improve on a retry.
        if (res.statusCode == 403 || res.statusCode == 404) return null;
      } catch (_) {
        // Timeout / dropped connection: try once more.
      }
    }
    return null;
  }

  /// Fetches then saves. Never throws: everything turns into a result the
  /// caller can put in front of the student.
  static Future<DocumentDownloadResult> download({
    required String url,
    required String fileName,
  }) async {
    if (url.isEmpty) {
      return const DocumentDownloadResult(
          false, 'No file is shared by the teacher yet.');
    }
    final bytes = await fetch(url);
    if (bytes == null || bytes.isEmpty) {
      return const DocumentDownloadResult(
        false,
        'Could not download the file. Check that you are connected to the '
        'teacher hotspot or classroom Wi-Fi.',
      );
    }
    return save(fileName, bytes);
  }

  /// Hands the bytes to the platform's save dialog.
  static Future<DocumentDownloadResult> save(
    String fileName,
    Uint8List bytes,
  ) async {
    final name = fileName.trim().isEmpty ? 'classcast-file' : fileName.trim();
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save $name',
        fileName: name,
        bytes: bytes,
        mimeType: mimeFor(name),
      );
      if (saved == null) {
        return const DocumentDownloadResult(false, 'Download cancelled.');
      }
      return DocumentDownloadResult(true, 'Saved $name');
    } catch (e) {
      return DocumentDownloadResult(false, 'Could not save the file: $e');
    }
  }

  static String mimeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.'
          'presentationml.presentation';
    }
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.'
          'wordprocessingml.document';
    }
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.'
          'spreadsheetml.sheet';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }
}
