/// Offline Excel (.xlsx) reader.
///
/// SpreadsheetML is a zip of XML, so sheets, cells, shared strings, number
/// formats, fonts, fills and merged ranges are parsed straight from the file.
/// Sheets are printed onto a **fixed** sheet page (see [kSheetPageWidthPt]) with
/// a fixed number of rows per page, so "page 2" means the same thing on the
/// teacher's phone and on every student's screen.
library;

import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'ooxml_package.dart';

/// Logical width of a printed sheet page, in points.
const double kSheetPageWidthPt = 720;
const double kSheetPageHeightPt = 792;
const double kSheetRowHeightPt = 20;
const int kRowsPerSheetPage = 34;

/// Upper bounds for painting. A worksheet may legally address XFD1048576;
/// rendering that would exhaust memory, so very wide/long sheets are clipped.
const int kMaxSheetColumns = 64;
const int kMaxSheetRows = 4000;

/// Ceiling on cells built across the whole workbook. Reached only by files
/// nobody can read on a phone anyway; the point is not to run out of memory.
const int kMaxWorkbookCells = 400000;

/// Excel's day zero for the 1900 date system (offset for its leap-year bug).
final DateTime _excelEpoch = DateTime.utc(1899, 12, 30);

enum XlsxAlign { left, center, right }

class XlsxCell {
  final String text;
  final bool bold;
  final bool italic;
  final double fontSizePt;
  final int color;
  final int? fill;
  final XlsxAlign align;
  final int colSpan;

  const XlsxCell({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.fontSizePt = 11,
    this.color = 0xFF000000,
    this.fill,
    this.align = XlsxAlign.left,
    this.colSpan = 1,
  });

  bool get isBlank => text.isEmpty && fill == null;

  XlsxCell copyWith({String? text, int? colSpan}) => XlsxCell(
        text: text ?? this.text,
        bold: bold,
        italic: italic,
        fontSizePt: fontSizePt,
        color: color,
        fill: fill,
        align: align,
        colSpan: colSpan ?? this.colSpan,
      );
}

class XlsxSheet {
  final String name;
  final List<List<XlsxCell>> rows;
  final List<double> columnWidthsPt;

  /// (row, col, rowSpan, colSpan) of merged ranges.
  final List<List<int>> merges;

  const XlsxSheet({
    required this.name,
    required this.rows,
    required this.columnWidthsPt,
    required this.merges,
  });

  int get rowCount => rows.length;

  int get columnCount => columnWidthsPt.length;

  int get pageCount => rowCount <= kRowsPerSheetPage
      ? 1
      : (rowCount / kRowsPerSheetPage).ceil();

  /// Rows shown on [page] (1-based).
  List<List<XlsxCell>> rowsOfPage(int page) {
    if (rows.isEmpty) return const [];
    final index = page.clamp(1, pageCount).toInt() - 1;
    final start = index * kRowsPerSheetPage;
    if (start >= rows.length) return const [];
    final end = start + kRowsPerSheetPage;
    return rows.sublist(start, end > rows.length ? rows.length : end);
  }
}

class XlsxWorkbook {
  final List<XlsxSheet> sheets;

  /// True when sheets were left out to stay inside the cell budget, so the UI
  /// can say the workbook was clipped instead of implying it was all shown.
  final bool clipped;

  const XlsxWorkbook({required this.sheets, this.clipped = false});

  int get sheetCount => sheets.length;

  /// Total printed pages across every sheet — the number the session syncs.
  int get pageCount =>
      sheets.fold<int>(0, (total, sheet) => total + sheet.pageCount);

  /// Maps a session page number onto a workbook sheet, so "page 7" still means
  /// something on a workbook with several sheets.
  ({XlsxSheet sheet, int pageInSheet})? excelPage(int page) {
    if (sheets.isEmpty) return null;
    var remaining = page < 1 ? 1 : page;
    for (final sheet in sheets) {
      if (remaining <= sheet.pageCount) {
        return (sheet: sheet, pageInSheet: remaining);
      }
      remaining -= sheet.pageCount;
    }
    final last = sheets.last;
    return (sheet: last, pageInSheet: last.pageCount);
  }

  /// Parses workbook bytes. Returns null when this is not a readable .xlsx.
  static XlsxWorkbook? parse(Uint8List bytes) {
    final pkg = OoxmlPackage.tryOpen(bytes);
    if (pkg == null || !pkg.hasWorkbook) return null;
    try {
      return _XlsxReader(pkg).read();
    } catch (_) {
      return null;
    }
  }
}

class _FontStyle {
  final bool bold;
  final bool italic;
  final double fontSizePt;
  final int color;

  const _FontStyle({
    this.bold = false,
    this.italic = false,
    this.fontSizePt = 11,
    this.color = 0xFF000000,
  });
}

class _CellFormat {
  final _FontStyle font;
  final int? fill;
  final XlsxAlign align;
  final int numFmtId;
  final String? numFmtCode;

  const _CellFormat({
    required this.font,
    this.fill,
    this.align = XlsxAlign.left,
    this.numFmtId = 0,
    this.numFmtCode,
  });
}

class _XlsxReader {
  final OoxmlPackage _pkg;
  final List<String> _sharedStrings = [];
  final List<_FontStyle> _fonts = [];
  final List<int?> _fills = [];
  final List<_CellFormat> _formats = [];
  final Map<int, String> _numFmts = {};

  _XlsxReader(this._pkg);

  XlsxWorkbook read() {
    _readSharedStrings();
    _readStyles();

    final workbook = _pkg.xml('xl/workbook.xml');
    if (workbook == null) throw const FormatException('missing xl/workbook.xml');
    final rels = _pkg.relationships('xl/workbook.xml');

    final sheets = <XlsxSheet>[];
    var clipped = false;
    final sheetsNode = findInDocument(workbook, 'sheets');
    if (sheetsNode != null) {
      // A dense sheet is rows x columns of cells, and one workbook can hold
      // many of them. Budgeting the whole workbook is what stops a real file
      // from allocating millions of cells on a phone.
      var budget = kMaxWorkbookCells;
      for (final sheet in childElements(sheetsNode, 'sheet')) {
        final name = attr(sheet, 'name') ?? 'Sheet';
        if (attr(sheet, 'state') == 'hidden') continue;
        final rid = relAttr(sheet, 'id');
        final part = rid == null ? null : rels[rid];
        if (part == null) continue;
        if (budget <= 0) {
          clipped = true;
          continue;
        }
        final parsed = _readSheet(part, name);
        if (parsed != null) {
          sheets.add(parsed);
          budget -= parsed.rowCount * kMaxSheetColumns;
        }
      }
    }
    return XlsxWorkbook(sheets: sheets, clipped: clipped);
  }

  void _readSharedStrings() {
    final doc = _pkg.xml('xl/sharedStrings.xml');
    if (doc == null) return;
    for (final si in findDescendants(doc, 'si')) {
      final buffer = StringBuffer();
      for (final t in findDescendants(si, 't')) {
        buffer.write(t.innerText);
      }
      _sharedStrings.add(buffer.toString());
    }
  }

  void _readStyles() {
    final doc = _pkg.xml('xl/styles.xml');
    if (doc == null) return;

    final numFmts = findInDocument(doc, 'numFmts');
    if (numFmts != null) {
      for (final fmt in childElements(numFmts, 'numFmt')) {
        final id = intAttr(fmt, 'numFmtId');
        final code = attr(fmt, 'formatCode');
        if (id != null && code != null) _numFmts[id] = code;
      }
    }

    final fonts = findInDocument(doc, 'fonts');
    if (fonts != null) {
      for (final font in childElements(fonts, 'font')) {
        final size = childElement(font, 'sz');
        final colorEl = childElement(font, 'color');
        _fonts.add(_FontStyle(
          bold: _on(childElement(font, 'b')) ||
              _on(childElement(font, 'bCs')),
          italic: _on(childElement(font, 'i')),
          fontSizePt:
              ((size == null ? null : doubleAttr(size, 'val')) ?? 11),
          color: _rgb(colorEl) ?? 0xFF000000,
        ));
      }
    }

    final fills = findInDocument(doc, 'fills');
    if (fills != null) {
      for (final fill in childElements(fills, 'fill')) {
        final pattern = childElement(fill, 'patternFill');
        final patternType = pattern == null ? null : attr(pattern, 'patternType');
        final fg = pattern == null ? null : childElement(pattern, 'fgColor');
        final rgb = _rgb(fg);
        // `none` / `gray125` are the two mandatory blank fills.
        if (patternType == null || patternType == 'none') {
          _fills.add(null);
        } else {
          _fills.add(rgb ?? _themeRgb(fg));
        }
      }
    }

    final cellXfs = findInDocument(doc, 'cellXfs');
    if (cellXfs != null) {
      for (final xf in childElements(cellXfs, 'xf')) {
        final fontId = intAttr(xf, 'fontId') ?? 0;
        final fillId = intAttr(xf, 'fillId') ?? 0;
        final numFmtId = intAttr(xf, 'numFmtId');
        final alignment = childElement(xf, 'alignment');
        final horizontal = alignment == null ? null : attr(alignment, 'horizontal');
        _formats.add(_CellFormat(
          font: fontId < _fonts.length
              ? _fonts[fontId]
              : const _FontStyle(),
          fill: fillId < _fills.length ? _fills[fillId] : null,
          align: switch (horizontal) {
            'center' || 'centerContinuous' => XlsxAlign.center,
            'right' => XlsxAlign.right,
            _ => XlsxAlign.left,
          },
          numFmtId: numFmtId ?? 0,
          numFmtCode: numFmtId == null ? null : _numFmts[numFmtId],
        ));
      }
    }
  }

  /// `<b/>` is true; `<b val="0"/>` is false.
  static bool _on(XmlElement? element) {
    if (element == null) return false;
    final val = attr(element, 'val');
    return val == null || (val != '0' && val != 'false');
  }

  static int? _rgb(XmlElement? element) {
    if (element == null) return null;
    return colorFromHexAttribute(attr(element, 'rgb'));
  }

  /// Indexed/theme colours fall back to the workbook's accent-less default.
  static int? _themeRgb(XmlElement? element) {
    if (element == null) return null;
    final theme = intAttr(element, 'theme') ?? 0;
    const byTheme = [
      0xFFFFFF,
      0x000000,
      0xEEECE1,
      0x1F497D,
      0x4F81BD,
      0xC0504D,
    ];
    if (theme < 0 || theme >= byTheme.length) return null;
    return byTheme[theme] | 0xFF000000;
  }

  XlsxSheet? _readSheet(String part, String name) {
    final doc = _pkg.xml(part);
    if (doc == null) return null;

    final widths = _readColumnWidths(doc);
    final grid = <int, Map<int, XlsxCell>>{};
    var maxRow = -1;
    var maxCol = -1;

    final data = findInDocument(doc, 'sheetData');
    if (data != null) {
      for (final row in childElements(data, 'row')) {
        final rowIndex = intAttr(row, 'r');
        final r = (rowIndex ?? (maxRow + 2)) - 1;
        // A worksheet may legally span XFD1048576; painting all of that would
        // exhaust memory, so the view is capped to classroom-sized sheets.
        if (r < 0 || r >= kMaxSheetRows) continue;
        var colCursor = -1;
        for (final cell in childElements(row, 'c')) {
          final reference = attr(cell, 'r');
          final column = reference == null
              ? colCursor + 1
              : _columnOf(reference) ?? (colCursor + 1);
          colCursor = column;
          if (column < 0 || column >= kMaxSheetColumns) continue;
          final parsed = _readCell(cell, column, r);
          if (parsed == null) continue;
          (grid[r] ??= {})[column] = parsed;
          if (r > maxRow) maxRow = r;
          if (column > maxCol) maxCol = column;
        }
      }
    }

    final columnCount = maxCol + 1;
    final rows = <List<XlsxCell>>[];
    for (var r = 0; r <= maxRow; r++) {
      final row = <XlsxCell>[];
      final source = grid[r];
      for (var c = 0; c < columnCount; c++) {
        row.add(source?[c] ?? const XlsxCell(text: ''));
      }
      rows.add(row);
    }

    final merges = _readMerges(doc);
    _applyMerges(rows, merges);

    return XlsxSheet(
      name: name,
      rows: rows,
      columnWidthsPt: _fitToPage(widths, columnCount),
      merges: merges,
    );
  }

  /// Folds merged ranges into the top-left cell so the renderer can paint a
  /// plain grid: the anchor keeps its text with the full column span, and the
  /// cells it covers are blanked out.
  static void _applyMerges(List<List<XlsxCell>> rows, List<List<int>> merges) {
    for (final merge in merges) {
      final row = merge[0];
      final column = merge[1];
      final colSpan = merge[3];
      if (row < 0 || row >= rows.length) continue;
      final line = rows[row];
      if (column < 0 || column >= line.length) continue;
      line[column] = line[column].copyWith(colSpan: colSpan < 1 ? 1 : colSpan);
      for (var r = row; r < row + merge[2] && r < rows.length; r++) {
        for (var c = column; c < column + colSpan && c < rows[r].length; c++) {
          if (r == row && c == column) continue;
          rows[r][c] = const XlsxCell(text: '');
        }
      }
    }
  }

  /// Excel column widths are in "characters"; converted to points and then
  /// scaled down when a wide sheet would not fit the fixed page width.
  static List<double> _fitToPage(List<double> widths, int columnCount) {
    final out = <double>[];
    var total = 0.0;
    for (var i = 0; i < columnCount; i++) {
      final width = i < widths.length && widths[i] > 0 ? widths[i] : 64;
      final pt = width * 5.5 + 6;
      out.add(pt);
      total += pt;
    }
    if (total > kSheetPageWidthPt && total > 0) {
      final factor = kSheetPageWidthPt / total;
      for (var i = 0; i < out.length; i++) {
        out[i] = out[i] * factor;
      }
    }
    return out;
  }

  List<double> _readColumnWidths(XmlDocument doc) {
    final out = <double>[];
    final cols = findInDocument(doc, 'cols');
    if (cols == null) return out;
    for (final col in childElements(cols, 'col')) {
      final min = intAttr(col, 'min') ?? 1;
      final max = intAttr(col, 'max') ?? min;
      final width = doubleAttr(col, 'width') ?? 0;
      for (var i = min; i <= max && i <= 256; i++) {
        while (out.length < i) {
          out.add(0);
        }
        if (i - 1 >= 0 && i - 1 < out.length) out[i - 1] = width;
      }
    }
    return out;
  }

  XlsxCell? _readCell(XmlElement cell, int column, int row) {
    final type = attr(cell, 't') ?? 'n';
    final styleId = intAttr(cell, 's');
    final format = (styleId != null && styleId >= 0 && styleId < _formats.length)
        ? _formats[styleId]
        : null;

    final value = childElement(cell, 'v');
    String text;
    switch (type) {
      case 's':
        final index = int.tryParse(value?.innerText ?? '');
        text = index != null && index < _sharedStrings.length
            ? _sharedStrings[index]
            : '';
        break;
      case 'inlineStr':
        final inline = childElement(cell, 'is');
        final buffer = StringBuffer();
        if (inline != null) {
          for (final t in findDescendants(inline, 't')) {
            buffer.write(t.innerText);
          }
        }
        text = buffer.toString();
        break;
      case 'b':
        text = (value?.innerText ?? '0').trim() == '1' ? 'TRUE' : 'FALSE';
        break;
      case 'e':
        text = value?.innerText ?? '';
        break;
      case 'str':
        text = value?.innerText ?? '';
        break;
      default:
        final raw = value?.innerText ?? '';
        text = _formatNumber(
          raw,
          format?.numFmtId ?? 0,
          format?.numFmtCode,
        );
        break;
    }

    // Style-only cells (empty but coloured) still paint their fill.
    if (text.isEmpty && format?.fill == null) return null;
    return XlsxCell(
      text: text,
      bold: format?.font.bold ?? false,
      italic: format?.font.italic ?? false,
      fontSizePt: format?.font.fontSizePt ?? 11,
      color: format?.font.color ?? 0xFF000000,
      fill: format?.fill,
      align: format?.align ?? XlsxAlign.left,
      colSpan: 1,
    );
  }

  /// Renders a numeric value with Excel's number formats applied where it is
  /// cheap to do so: dates and built-in rounding.
  static String _formatNumber(String raw, int numFmtId, String? numFmtCode) {
    final value = double.tryParse(raw.trim());
    if (value == null) return raw;
    if (_isDateNumberFormat(numFmtId, numFmtCode)) {
      return _formatDate(value, numFmtCode);
    }
    if (raw.contains('.')) {
      // Keep the author's own precision instead of Dart's exponent formatting.
      final trimmed = raw.trim();
      if (trimmed.endsWith('.0')) return trimmed.substring(0, trimmed.length - 2);
    }
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return raw;
  }

  /// Dates are either one of Excel's built-in ids (which have no entry in
  /// `numFmts`) or a custom code that contains date/time placeholders.
  static bool _isDateNumberFormat(int numFmtId, String? code) {
    if ((numFmtId >= 14 && numFmtId <= 22) ||
        (numFmtId >= 45 && numFmtId <= 47)) {
      return true;
    }
    // General, which is what almost every numeric cell in a plain sheet
    // carries. No code, no sniffing, no string work.
    if (code == null || code.isEmpty) return false;
    // Strip quoted literals before sniffing for date/time placeholders.
    final clean = code.replaceAll(_quotedLiteral, '').toLowerCase();
    if (clean.isEmpty || clean == 'general') return false;
    final withoutLiterals = clean.replaceAll(_bracketedLiteral, '');
    if (withoutLiterals.contains('yy') || withoutLiterals.contains('dd')) {
      return true;
    }
    return _datePlaceholder.hasMatch(withoutLiterals);
  }

  static String _formatDate(double serial, String? code) {
    if (serial < 1 || serial > 2958466) return serial.toInt().toString();
    final moment = _excelEpoch.add(Duration(hours: (serial * 24).round()));
    final clean = (code ?? '').replaceAll(_quotedLiteral, '').toLowerCase();
    final hasTime = clean.contains('h') || clean.contains('s');
    final y = moment.year.toString().padLeft(4, '0');
    final m = moment.month.toString().padLeft(2, '0');
    final d = moment.day.toString().padLeft(2, '0');
    final time = '${moment.hour.toString().padLeft(2, '0')}:'
        '${moment.minute.toString().padLeft(2, '0')}';
    if (!hasTime) return '$y-$m-$d';
    return '$y-$m-$d $time';
  }

  static List<List<int>> _readMerges(XmlDocument doc) {
    final out = <List<int>>[];
    final node = findInDocument(doc, 'mergeCells');
    if (node == null) return out;
    for (final merge in childElements(node, 'mergeCell')) {
      final ref = attr(merge, 'ref');
      if (ref == null) continue;
      final parts = ref.split(':');
      if (parts.length != 2) continue;
      final from = parts[0];
      final to = parts[1];
      final row1 = _rowOf(from);
      final col1 = _columnOf(from);
      final row2 = _rowOf(to);
      final col2 = _columnOf(to);
      if (row1 == null || col1 == null || row2 == null || col2 == null) continue;
      out.add([row1, col1, row2 - row1 + 1, col2 - col1 + 1]);
    }
    return out;
  }

  static int? _rowOf(String reference) {
    final digits = _digits.firstMatch(reference)?.group(1);
    return digits == null ? null : int.parse(digits) - 1;
  }

  static int? _columnOf(String reference) {
    final letters = _letters.firstMatch(reference)?.group(1);
    if (letters == null) return null;
    var value = 0;
    for (final ch in letters.toUpperCase().split('')) {
      final code = ch.codeUnitAt(0);
      if (code < 65 || code > 90) return null;
      value = value * 26 + (code - 64);
    }
    return value - 1;
  }

  /// Compiled once, not per call.
  ///
  /// The VM does not cache a `RegExp` the way it caches a string, so these
  /// were rebuilt on every invocation. `_columnOf` runs once per cell and
  /// `_isDateNumberFormat` up to three times per numeric cell, which on a
  /// dense workbook is hundreds of thousands of compilations — more time than
  /// the rest of the parse put together.
  static final _quotedLiteral = RegExp(r'"[^"]*"');
  static final _bracketedLiteral = RegExp(r'\[[^\]]*\]');
  static final _datePlaceholder = RegExp(r'[dmyh]');
  static final _digits = RegExp(r'(\d+)');
  static final _letters = RegExp(r'([A-Za-z]+)');
}
