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
    if (bytes == null || bytes.isEmpty) {
      _lastFailure = bytes == null
          ? 'The file could not be read from this device or from the teacher.'
          : 'The file came back empty.';
      return null;
    }
    // On a background isolate. Inflating a 64 MB archive and walking every
    // slide's XML is seconds of straight-line work, and `await` alone does not
    // get it off this thread — only compute does. It was the difference
    // between tapping a deck and watching the whole app stop until it opened.
    OoxmlDocument? parsed;
    _lastFailure = null;
    try {
      parsed = await compute(parseIn, <String, Object?>{
        'extension': extension,
        'bytes': bytes,
        'onError': (String reason) => _lastFailure = reason,
      });
    } catch (_) {
      // The isolate is a nicety, not a requirement. If the message is too big
      // to send, or the isolate cannot be spawned, parsing inline is slow but
      // it still opens the file — and reporting "could not open this file" for
      // a deck that is perfectly readable is the worst possible answer.
      parsed = parseBytes(extension: extension, bytes: bytes);
    }
    if (parsed != null) {
      _remember(source, parsed);
    }
    return parsed;
  }

  /// Why the last [load] failed, in a sentence the teacher can act on.
  ///
  /// Held on the singleton rather than returned alongside the document, which
  /// would mean threading a result type through every caller for a value that
  /// only matters on the failure path. The failure is read immediately, by the
  /// screen that is about to show it.
  static String? _lastFailure;

  static String? get lastFailure => _lastFailure;

  /// The `compute` entry point: takes a map, returns the parsed document.
  ///
  /// Static because `compute` needs a plain function it can send to another
  /// isolate, and because the whole message — a `Map` of a `String` and a
  /// `Uint8List` — and the whole result are plain data. Nothing under
  /// [OoxmlDocument] holds on to an `XmlNode`, which is what makes that safe;
  /// the DOM is read during the parse and dropped before it returns.
  ///
  /// `onError` rides along in the map as a closure, which is what lets the
  /// reason come back off the isolate: functions are sendable in Dart 3.
  static OoxmlDocument? parseIn(Map<String, Object?> message) {
    final bytes = message['bytes'] as Uint8List?;
    final extension = message['extension'] as String? ?? '';
    final onError = message['onError'];
    void report(String reason) {
      if (onError is void Function(String)) onError(reason);
    }

    if (bytes == null || bytes.isEmpty) {
      report('Nothing arrived — the file came back empty.');
      return null;
    }
    return parseBytes(extension: extension, bytes: bytes, onError: report);
  }

  /// Parses bytes already in hand. Exposed for tests.
  static OoxmlDocument? parseBytes({
    required String extension,
    required Uint8List bytes,
    void Function(String)? onError,
  }) {
    final ext = extension.toLowerCase().replaceAll('.', '');
    if (OoxmlFileTypes.powerpoint.contains(ext)) {
      final deck = PptxDeck.parse(bytes, onError: onError);
      return deck == null ? null : OoxmlDocument.powerpoint(deck);
    }
    if (OoxmlFileTypes.word.contains(ext)) {
      final doc = DocxDocument.parse(bytes, onError: onError);
      return doc == null ? null : OoxmlDocument.word(doc);
    }
    if (OoxmlFileTypes.excel.contains(ext)) {
      final book = XlsxWorkbook.parse(bytes, onError: onError);
      return book == null ? null : OoxmlDocument.excel(book);
    }
    onError?.call('A .$ext file is not one the app can open.');
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
      // Twice, because the most likely reason a student's copy of a deck will
      // not open is that the transfer over the hotspot stopped part way and
      // left a truncated zip. A retry costs a second and actually fixes it;
      // the alternative is telling the teacher their file is damaged.
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await http.get(Uri.parse(remoteUrl)).timeout(
                const Duration(seconds: 30),
              );
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            return response.bodyBytes;
          }
        } catch (_) {
          if (attempt == 1) return null;
        }
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
