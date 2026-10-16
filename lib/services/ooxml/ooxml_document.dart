import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../utils/local_file.dart';
import 'docx_document.dart';
import 'pptx_deck.dart';
import 'xlsx_workbook.dart';

/// Office formats the app can open by itself, with no laptop conversion step.
enum OoxmlFormat { powerpoint, word, excel }

/// Result of opening an Office file: exactly one of the three payloads is set.
class OoxmlDocument {
  final OoxmlFormat format;
  final PptxDeck? deck;
  final DocxDocument? word;
  final XlsxWorkbook? workbook;

  const OoxmlDocument.powerpoint(this.deck)
      : format = OoxmlFormat.powerpoint,
        word = null,
        workbook = null;

  const OoxmlDocument.word(this.word)
      : format = OoxmlFormat.word,
        deck = null,
        workbook = null;

  const OoxmlDocument.excel(this.workbook)
      : format = OoxmlFormat.excel,
        deck = null,
        word = null;

  /// Slides / pages / printed sheet pages, matching what the session syncs.
  int get pageCount => switch (format) {
        OoxmlFormat.powerpoint => deck?.slideCount ?? 0,
        OoxmlFormat.word => word?.pageCount ?? 0,
        OoxmlFormat.excel => workbook?.pageCount ?? 0,
      };
}

/// Loads Office files once and keeps the parsed result around.
///
/// The teacher flips through the same deck for a whole lesson, and every page
/// change asks the viewer to redraw; re-reading and re-parsing the file on each
/// redraw is what made presentations stutter, so the parse is cached by source.
class OoxmlLoader {
  OoxmlLoader._();

  static final OoxmlLoader instance = OoxmlLoader._();

  static const int _maxCached = 6;

  final Map<String, OoxmlDocument> _cache = {};

  /// Parsed document already in memory for this source, if any.
  OoxmlDocument? peek(String source) => _cache[source];

  /// Drops everything parsed so far.
  ///
  /// Called when a session ends: a photo-heavy deck holds its images as raw
  /// bytes, and six of those stay resident until the app is killed.
  void clear() => _cache.clear();

  /// Opens the file from the teacher's device, falling back to the bytes the
  /// teacher host serves to students. Null means "cannot open", and the caller
  /// shows an honest panel instead of a blank screen.
  Future<OoxmlDocument?> load({
    required String extension,
    String? localPath,
    String? remoteUrl,
  }) async {
    final source = sourceKey(extension, localPath, remoteUrl);
    if (source == null) return null;
    final cached = _cache[source];
    if (cached != null) return cached;

    final bytes = await _readBytes(localPath, remoteUrl);
    if (bytes == null || bytes.isEmpty) return null;
    // On a background isolate. Inflating a 64 MB archive and walking every
    // slide's XML is seconds of straight-line work, and `await` alone does not
    // get it off this thread — only compute does. It was the difference
    // between tapping a deck and watching the whole app stop until it opened.
    final parsed = await compute(parseIn, <String, Object?>{
      'extension': extension,
      'bytes': bytes,
    });
    if (parsed != null) {
      _remember(source, parsed);
    }
    return parsed;
  }

  /// The `compute` entry point: takes a map, returns the parsed document.
  ///
  /// Static because `compute` needs a plain function it can send to another
  /// isolate, and because the whole message — a `Map` of a `String` and a
  /// `Uint8List` — and the whole result are plain data. Nothing under
  /// [OoxmlDocument] holds on to an `XmlNode`, which is what makes that safe;
  /// the DOM is read during the parse and dropped before it returns.
  static OoxmlDocument? parseIn(Map<String, Object?> message) {
    final bytes = message['bytes'] as Uint8List?;
    final extension = message['extension'] as String? ?? '';
    if (bytes == null || bytes.isEmpty) return null;
    return parseBytes(extension: extension, bytes: bytes);
  }

  /// Parses bytes already in hand. Exposed for tests.
  static OoxmlDocument? parseBytes({
    required String extension,
    required Uint8List bytes,
  }) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    if (OoxmlFileTypes.powerpoint.contains(ext)) {
      final deck = PptxDeck.parse(bytes);
      return deck == null ? null : OoxmlDocument.powerpoint(deck);
    }
    if (OoxmlFileTypes.word.contains(ext)) {
      final doc = DocxDocument.parse(bytes);
      return doc == null ? null : OoxmlDocument.word(doc);
    }
    if (OoxmlFileTypes.excel.contains(ext)) {
      final book = XlsxWorkbook.parse(bytes);
      return book == null ? null : OoxmlDocument.excel(book);
    }
    return null;
  }

  /// Cache identity for a file: its device path, else the host URL.
  static String? sourceKey(
      String extension, String? localPath, String? remoteUrl) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    if (localPath != null && localPath.isNotEmpty) {
      return 'file:$ext:${localPath.toLowerCase()}';
    }
    if (remoteUrl != null && remoteUrl.isNotEmpty) return 'url:$remoteUrl';
    return null;
  }

  /// Least-recently-used eviction: a lesson touches a few files, a long session
  /// must not accumulate every deck the teacher ever opened.
  void _remember(String source, OoxmlDocument document) {
    _cache.remove(source);
    _cache[source] = document;
    while (_cache.length > _maxCached) {
      _cache.remove(_cache.keys.first);
    }
  }

  static Future<Uint8List?> _readBytes(
    String? localPath,
    String? remoteUrl,
  ) async {
    if (localPath != null && localPath.isNotEmpty) {
      final local = await localFileReadBytes(localPath);
      if (local != null && local.isNotEmpty) return local;
    }
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(remoteUrl)).timeout(
              const Duration(seconds: 30),
            );
        if (response.statusCode == 200) return response.bodyBytes;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

/// Extensions per Office format, including the legacy binary ones that cannot
/// be opened on device (they are not zip containers).
class OoxmlFileTypes {
  static const powerpoint = ['pptx'];
  static const word = ['docx'];
  static const excel = ['xlsx'];

  /// PowerPoint 97-2003 binary format: an OLE compound file, not a zip.
  static const legacyPowerpoint = ['ppt'];

  /// Word 97-2003 binary format.
  static const legacyWord = ['doc'];

  /// Excel 97-2003 binary format.
  static const legacyExcel = ['xls'];

  static bool isLegacy(String extension) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    return legacyPowerpoint.contains(ext) ||
        legacyWord.contains(ext) ||
        legacyExcel.contains(ext);
  }
}
