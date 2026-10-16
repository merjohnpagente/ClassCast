/// Offline Word (.docx) reader.
///
/// WordprocessingML is a zip of XML, so paragraphs, runs, tables, lists and
/// inline pictures are parsed straight from the file and laid out by the app.
/// A .docx has no fixed page boxes, so pages are computed from a **fixed**
/// page geometry ([kPageWidthPt] × [kPageHeightPt] with one-inch margins).
/// That makes pagination deterministic: the teacher and every student agree on
/// what "page 3" is, on any screen size.
library;

import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'ooxml_package.dart';

/// US Letter, the most common Word page size.
const double kPageWidthPt = 612;
const double kPageHeightPt = 792;
const double kPageMarginPt = 72;
const double kPageContentWidthPt = kPageWidthPt - 2 * kPageMarginPt;
const double kPageContentHeightPt = kPageHeightPt - 2 * kPageMarginPt;

enum DocxAlign { left, center, right, justify }

class DocxRun {
  final String text;
  final double fontSizePt;
  final bool bold;
  final bool italic;
  final bool underline;
  final int color;
  final String? typeface;

  /// Inline picture, when this "run" is really a drawing.
  final Uint8List? image;
  final double imageWidthPt;
  final double imageHeightPt;

  const DocxRun({
    required this.text,
    this.fontSizePt = 11,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color = 0xFF000000,
    this.typeface,
    this.image,
    this.imageWidthPt = 0,
    this.imageHeightPt = 0,
  });

  bool get isImage => image != null;
}

class DocxParagraph {
  final List<DocxRun> runs;
  final DocxAlign align;
  final double indentLeftPt;
  final double firstLineIndentPt;
  final double spaceBeforePt;
  final double spaceAfterPt;
  final String bullet;
  final int headingLevel;

  /// A hard page break typed in the document (`Ctrl+Enter`).
  final bool pageBreakBefore;

  const DocxParagraph({
    required this.runs,
    this.align = DocxAlign.left,
    this.indentLeftPt = 0,
    this.firstLineIndentPt = 0,
    this.spaceBeforePt = 0,
    this.spaceAfterPt = 0,
    this.bullet = '',
    this.headingLevel = 0,
    this.pageBreakBefore = false,
  });

  String get plainText =>
      runs.where((r) => !r.isImage).map((r) => r.text).join();

  bool get isEmpty => plainText.trim().isEmpty && runs.every((r) => !r.isImage);
}

class DocxTableCell {
  final List<DocxParagraph> paragraphs;
  final int colSpan;
  final int fill;

  const DocxTableCell({
    required this.paragraphs,
    this.colSpan = 1,
    this.fill = 0x00000000,
  });
}

class DocxTable {
  final List<List<DocxTableCell>> rows;
  final List<double> columnWidthsPt;

  const DocxTable({required this.rows, required this.columnWidthsPt});
}

/// Anything that can appear in the document flow.
class DocxBlock {
  final DocxParagraph? paragraph;
  final DocxTable? table;

  const DocxBlock.paragraph(DocxParagraph this.paragraph) : table = null;

  const DocxBlock.table(DocxTable this.table) : paragraph = null;

  bool get isTable => table != null;
}

class DocxDocument {
  final String title;
  final List<DocxBlock> blocks;

  /// Index of the first block on each page.
  final List<int> _pageStarts;

  const DocxDocument({
    required this.title,
    required this.blocks,
    required List<int> pageStarts,
  }) : _pageStarts = pageStarts;

  int get pageCount => _pageStarts.isEmpty ? 1 : _pageStarts.length;

  /// Blocks that belong to [page] (1-based).
  List<DocxBlock> blocksOfPage(int page) {
    if (_pageStarts.isEmpty) return blocks;
    final index = page.clamp(1, _pageStarts.length).toInt() - 1;
    final start = _pageStarts[index];
    final end = index + 1 < _pageStarts.length ? _pageStarts[index + 1] : blocks.length;
    if (start >= end) return const [];
    return blocks.sublist(start, end);
  }

  /// Parses document bytes. Returns null when this is not a readable .docx.
  static DocxDocument? parse(Uint8List bytes, {void Function(String)? onError}) {
    final pkg = OoxmlPackage.tryOpen(bytes, onError: onError);
    if (pkg == null) return null;
    if (!pkg.hasWordDocument) {
      onError?.call("There is no word/document.xml in the archive, so this is "
          "not a Word file.");
      return null;
    }
    try {
      final reader = _DocxReader(pkg);
      return reader.read();
    } catch (e) {
      onError?.call("The document could not be read: $e");
      return null;
    }
  }
}

/// Paragraph and character defaults resolved from `word/styles.xml`.
class _Style {
  final String id;
  final int headingLevel;
  final double fontSizePt;
  final bool bold;
  final int color;

  const _Style({
    required this.id,
    required this.headingLevel,
    required this.fontSizePt,
    required this.bold,
    required this.color,
  });
}

class _NumberingLevel {
  final String format;
  final String text;

  const _NumberingLevel(this.format, this.text);
}

class _DocxReader {
  final OoxmlPackage _pkg;
  final String _part = 'word/document.xml';

  double _defaultSizePt = 11;
  final Map<String, _Style> _styles = {};
  final Map<String, Map<int, _NumberingLevel>> _numbering = {};
  final Map<String, int> _numberingCounters = {};

  _DocxReader(this._pkg);

  DocxDocument read() {
    final doc = _pkg.xml(_part);
    if (doc == null) throw const FormatException('missing word/document.xml');
    _readStyles();
    _readNumbering();

    final body = findInDocument(doc, 'body');
    final blocks = <DocxBlock>[];
    if (body != null) {
      for (final node in body.children.whereType<XmlElement>()) {
        switch (node.localName) {
          case 'p':
            blocks.add(DocxBlock.paragraph(_readParagraph(node)));
            break;
          case 'tbl':
            final table = _readTable(node);
            if (table != null) blocks.add(DocxBlock.table(table));
            break;
          default:
            break;
        }
      }
    }

    return DocxDocument(
      title: _readTitle(),
      blocks: blocks,
      pageStarts: _paginate(blocks),
    );
  }

  String _readTitle() {
    final core = _pkg.xml('docprops/core.xml');
    if (core == null) return '';
    final title = findInDocument(core, 'title');
    final value = title?.innerText.trim() ?? '';
    return value;
  }

  void _readStyles() {
    final doc = _pkg.xml('word/styles.xml');
    if (doc == null) return;
    final defaults = findInDocument(doc, 'docDefaults');
    final rPrDefault = defaults == null ? null : findDescendant(defaults, 'rPrDefault');
    final defaultRPr = rPrDefault == null ? null : childElement(rPrDefault, 'rPr');
    final defaultSize = defaultRPr == null ? null : childElement(defaultRPr, 'sz');
    _defaultSizePt = ((defaultSize == null ? null : intAttr(defaultSize, 'val')) ?? 22) / 2;

    for (final style in childElements(doc, 'style')) {
      final id = attr(style, 'styleId');
      if (id == null || id.isEmpty) continue;
      final name = childElement(style, 'name');
      final nameValue = name == null ? '' : (attr(name, 'val') ?? '');
      final rPr = childElement(style, 'rPr');
      final size = rPr == null ? null : childElement(rPr, 'sz');
      final sizeVal = size == null ? null : intAttr(size, 'val');
      final color = rPr == null ? null : childElement(rPr, 'color');
      _styles[id] = _Style(
        id: id,
        headingLevel: _headingLevelOf(id, nameValue),
        fontSizePt:
            sizeVal != null && sizeVal > 0 ? sizeVal / 2 : _defaultSizePt,
        bold: _flag(rPr, 'b') ?? nameValue.toLowerCase().contains('heading'),
        color: colorFromHexAttribute(
                color == null ? null : attr(color, 'val')) ??
            0xFF000000,
      );
    }
  }

  /// Word style names are localized, so the id is trusted first.
  static int _headingLevelOf(String id, String name) {
    final byId = _headingId.firstMatch(id);
    if (byId != null) return int.parse(byId.group(1)!);
    final byName = _headingName.firstMatch(name);
    if (byName != null) return int.parse(byName.group(1)!);
    if (id.toLowerCase() == 'title') return 1;
    return 0;
  }

  /// Compiled once. This runs for every entry in `styles.xml`, and the VM does
  /// not cache a `RegExp` the way it caches a string.
  static final _headingId =
      RegExp(r'^heading(\d)$', caseSensitive: false);
  static final _headingName =
      RegExp(r'^heading\s*(\d)', caseSensitive: false);

  void _readNumbering() {
    final doc = _pkg.xml('word/numbering.xml');
    if (doc == null) return;
    final abstracts = <String, Map<int, _NumberingLevel>>{};
    for (final abstractNum in childElements(doc, 'abstractNum')) {
      final id = attr(abstractNum, 'abstractNumId');
      if (id == null) continue;
      final levels = <int, _NumberingLevel>{};
      for (final lvl in childElements(abstractNum, 'lvl')) {
        final ilvl = intAttr(lvl, 'ilvl') ?? 0;
        final fmt = childElement(lvl, 'numFmt');
        final text = childElement(lvl, 'lvlText');
        levels[ilvl] = _NumberingLevel(
          fmt == null ? 'bullet' : (attr(fmt, 'val') ?? 'bullet'),
          text == null ? '•' : (attr(text, 'val') ?? '•'),
        );
      }
      abstracts[id] = levels;
    }
    for (final num in childElements(doc, 'num')) {
      final numId = attr(num, 'numId');
      final abstractRef = childElement(num, 'abstractNumId');
      final abstractId =
          abstractRef == null ? null : attr(abstractRef, 'val');
      if (numId == null || abstractId == null) continue;
      final levels = abstracts[abstractId];
      if (levels != null) _numbering[numId] = levels;
    }
  }

  DocxParagraph _readParagraph(XmlElement p) {
    final pPr = childElement(p, 'pPr');
    final styleId = pPr == null ? null : _styleIdOf(pPr);
    final style = styleId == null ? null : _styles[styleId];

    final runs = _readRuns(p, style);
    final level = style?.headingLevel ?? 0;
    final bullet = _bulletFor(pPr, level);
    final spacing = pPr == null ? null : childElement(pPr, 'spacing');
    final beforeTwips = spacing == null ? null : intAttr(spacing, 'before');
    final afterTwips = spacing == null ? null : intAttr(spacing, 'after');

    final indent = pPr == null ? null : childElement(pPr, 'ind');
    final hangingTwips = indent == null ? null : intAttr(indent, 'hanging');
    final firstLineTwips = indent == null ? null : intAttr(indent, 'firstLine');
    final indentLeftTwips = (indent == null ? null : intAttr(indent, 'left')) ??
        (bullet.isEmpty ? 0 : 18 * 20);

    return DocxParagraph(
      runs: runs,
      align: _alignOf(pPr),
      indentLeftPt: indentLeftTwips / kTwipsPerPoint,
      firstLineIndentPt: hangingTwips != null
          ? -hangingTwips / kTwipsPerPoint
          : (firstLineTwips ?? 0) / kTwipsPerPoint,
      // Word stores spacing in twips; headings get breathing room by default.
      spaceBeforePt:
          beforeTwips == null ? (level > 0 ? 12.0 : 0.0) : beforeTwips / kTwipsPerPoint,
      spaceAfterPt: afterTwips == null
          ? (level > 0 ? 6.0 : 4.0)
          : afterTwips / kTwipsPerPoint,
      bullet: bullet,
      headingLevel: level,
      pageBreakBefore: _hasPageBreak(p),
    );
  }

  static String? _styleIdOf(XmlElement pPr) {
    final pStyle = childElement(pPr, 'pStyle');
    return pStyle == null ? null : attr(pStyle, 'val');
  }

  static DocxAlign _alignOf(XmlElement? pPr) {
    final jc = pPr == null ? null : childElement(pPr, 'jc');
    switch (jc == null ? null : attr(jc, 'val')) {
      case 'center':
        return DocxAlign.center;
      case 'right':
      case 'end':
        return DocxAlign.right;
      case 'both':
      case 'distribute':
        return DocxAlign.justify;
      default:
        return DocxAlign.left;
    }
  }

  static bool _hasPageBreak(XmlElement p) {
    for (final br in findDescendants(p, 'br')) {
      if (attr(br, 'type') == 'page') return true;
    }
    return findDescendant(p, 'lastRenderedPageBreak') != null;
  }

  /// Bullet / number marker for a list paragraph, or '' when not a list.
  String _bulletFor(XmlElement? pPr, int headingLevel) {
    if (headingLevel > 0) return '';
    if (pPr == null) return '';
    final numPr = childElement(pPr, 'numPr');
    if (numPr == null) return '';
    final numIdEl = childElement(numPr, 'numId');
    final ilvlEl = childElement(numPr, 'ilvl');
    final numId = numIdEl == null ? null : attr(numIdEl, 'val');
    final ilvl = (ilvlEl == null ? null : intAttr(ilvlEl, 'val')) ?? 0;
    if (numId == null) return '•';
    final level = _numbering[numId]?[ilvl];
    if (level == null) return '•';

    final key = '$numId:$ilvl';
    if (level.format == 'bullet' || level.format == 'none') {
      return level.text.isEmpty ? '•' : level.text;
    }
    final count = (_numberingCounters[key] ?? 0) + 1;
    _numberingCounters[key] = count;
    // `%1.`-style patterns reference the level's own counter.
    return level.text.replaceAll('%${ilvl + 1}', '$count');
  }

  List<DocxRun> _readRuns(XmlElement p, _Style? style) {
    final runs = <DocxRun>[];
    for (final node in p.children.whereType<XmlElement>()) {
      switch (node.localName) {
        case 'r':
          runs.addAll(_readRun(node, style));
          break;
        case 'hyperlink':
          for (final inner in childElements(node, 'r')) {
            runs.addAll(_readRun(inner, style));
          }
          break;
        case 'smartTag':
        case 'ins':
          for (final inner in childElements(node, 'r')) {
            runs.addAll(_readRun(inner, style));
          }
          break;
        default:
          break;
      }
    }
    return runs;
  }

  List<DocxRun> _readRun(XmlElement r, _Style? style) {
    final out = <DocxRun>[];
    final rPr = childElement(r, 'rPr');
    final sizeHalfPoints = rPr == null ? null : _halfPoints(rPr, 'sz');
    final fontSizePt = sizeHalfPoints != null && sizeHalfPoints > 0
        ? sizeHalfPoints / 2
        : (style?.fontSizePt ?? _defaultSizePt);
    final bold = _flag(rPr, 'b') ?? style?.bold ?? false;
    final italic = _flag(rPr, 'i') ?? false;
    final underlineEl = rPr == null ? null : childElement(rPr, 'u');
    final underline = underlineEl != null &&
        (attr(underlineEl, 'val') ?? 'single') != 'none';
    final colorEl = rPr == null ? null : childElement(rPr, 'color');
    final color = colorFromHexAttribute(colorEl == null ? null : attr(colorEl, 'val')) ??
        style?.color ??
        0xFF000000;
    final fonts = rPr == null ? null : childElement(rPr, 'rFonts');
    final typeface = fonts == null ? null : attr(fonts, 'ascii');

    final drawing = childElement(r, 'drawing');
    if (drawing != null) {
      final blip = findDescendant(drawing, 'blip');
      final rid = blip == null ? null : relAttr(blip, 'embed');
      final extent = findDescendant(drawing, 'extent');
      final bytes = rid == null ? null : _pkg.relatedBytes(_part, rid);
      if (bytes != null && bytes.isNotEmpty) {
        out.add(DocxRun(
          text: '',
          fontSizePt: fontSizePt,
          image: bytes,
          imageWidthPt: pointsAttr(extent, 'cx'),
          imageHeightPt: pointsAttr(extent, 'cy'),
        ));
      }
      return out;
    }

    // Legacy VML pictures (`<w:pict><v:imagedata r:id="…"/>`).
    final pict = childElement(r, 'pict');
    if (pict != null) {
      final data = findDescendant(pict, 'imagedata');
      final rid = data == null ? null : relAttr(data, 'id');
      final bytes = rid == null ? null : _pkg.relatedBytes(_part, rid);
      if (bytes != null && bytes.isNotEmpty) {
        out.add(DocxRun(
          text: '',
          fontSizePt: fontSizePt,
          image: bytes,
          imageWidthPt: 180,
          imageHeightPt: 120,
        ));
      }
      return out;
    }

    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      out.add(DocxRun(
        text: buffer.toString(),
        fontSizePt: fontSizePt,
        bold: bold,
        italic: italic,
        underline: underline,
        color: color,
        typeface: typeface,
      ));
      buffer.clear();
    }

    for (final node in r.children.whereType<XmlElement>()) {
      switch (node.localName) {
        case 't':
          buffer.write(node.innerText);
          break;
        case 'tab':
          buffer.write('\t');
          break;
        case 'br':
        case 'cr':
          buffer.write('\n');
          break;
        case 'noBreakHyphen':
          buffer.write('-');
          break;
        case 'sym':
          final code = attr(node, 'char');
          if (code != null) {
            final value = int.tryParse(code, radix: 16);
            if (value != null) buffer.writeCharCode(value);
          }
          break;
        default:
          break;
      }
    }
    flush();
    return out;
  }

  static int? _halfPoints(XmlElement rPr, String name) {
    final el = childElement(rPr, name);
    if (el == null) return null;
    return intAttr(el, 'val');
  }

  /// `<w:b/>` means true; `<w:b w:val="0"/>` means false; absent means
  /// "inherit", which the caller resolves.
  static bool? _flag(XmlElement? rPr, String name) {
    if (rPr == null) return null;
    final el = childElement(rPr, name);
    if (el == null) return null;
    final val = attr(el, 'val');
    if (val == null) return true;
    return val != '0' && val != 'false';
  }

  DocxTable? _readTable(XmlElement tbl) {
    final widths = <double>[];
    final grid = childElement(tbl, 'tblGrid');
    if (grid != null) {
      for (final col in childElements(grid, 'gridCol')) {
        widths.add((intAttr(col, 'w') ?? 0) / kTwipsPerPoint);
      }
    }

    final rows = <List<DocxTableCell>>[];
    for (final tr in childElements(tbl, 'tr')) {
      final row = <DocxTableCell>[];
      for (final tc in childElements(tr, 'tc')) {
        final tcPr = childElement(tc, 'tcPr');
        final shade = tcPr == null ? null : childElement(tcPr, 'shd');
        final paragraphs = <DocxParagraph>[];
        for (final node in tc.children.whereType<XmlElement>()) {
          if (node.localName == 'p') paragraphs.add(_readParagraph(node));
        }
        final vMerge = tcPr == null ? null : childElement(tcPr, 'vMerge');
        // A continuation cell of a vertical merge repeats the row above; the
        // cell is skipped so the merge renders as one block.
        final isMergeContinuation = vMerge != null &&
            (attr(vMerge, 'val') ?? 'continue') == 'continue';
        if (isMergeContinuation) continue;
        row.add(DocxTableCell(
          paragraphs: paragraphs,
          colSpan: countChild(tcPr, 'gridSpan', 1),
          fill: colorFromHexAttribute(shade == null ? null : attr(shade, 'fill')) ??
              0x00000000,
        ));
      }
      if (row.isNotEmpty) rows.add(row);
    }
    if (rows.isEmpty) return null;
    if (widths.isEmpty) {
      final columns = rows.first.length;
      final each = kPageContentWidthPt / (columns == 0 ? 1 : columns);
      return DocxTable(
        rows: rows,
        columnWidthsPt: List<double>.filled(columns, each),
      );
    }
    return DocxTable(rows: rows, columnWidthsPt: widths);
  }

  /// Greedy, deterministic pagination over the fixed page box.
  ///
  /// Word does not store page breaks, so heights are estimated from font size
  /// and text length. The same estimate runs on every device, which is what
  /// keeps teacher and students on the same slide number.
  List<int> _paginate(List<DocxBlock> blocks) {
    final starts = <int>[0];
    var used = 0.0;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final paragraph = block.paragraph;
      if (paragraph != null && paragraph.pageBreakBefore && i > starts.last) {
        starts.add(i);
        used = 0;
      }
      final height = _heightOf(block, kPageContentWidthPt);
      if (used > 0 && used + height > kPageContentHeightPt) {
        starts.add(i);
        used = 0;
      }
      used += height;
    }
    return starts;
  }

  double _heightOf(DocxBlock block, double availableWidth) {
    final table = block.table;
    if (table == null) return _paragraphHeight(block.paragraph!, availableWidth);
    var height = 0.0;
    for (final row in table.rows) {
      var rowHeight = 16.0;
      for (final cell in row) {
        var cellHeight = 0.0;
        for (final paragraph in cell.paragraphs) {
          cellHeight += _paragraphHeight(paragraph, availableWidth / 2);
        }
        if (cellHeight > rowHeight) rowHeight = cellHeight;
      }
      height += rowHeight + 2;
    }
    return height;
  }

  static double _paragraphHeight(DocxParagraph p, double availableWidth) {
    var fontSize = p.runs.isEmpty
        ? 11.0
        : p.runs
            .where((r) => r.text.isNotEmpty)
            .map((r) => r.fontSizePt)
            .fold<double>(0, (a, b) => a > b ? a : b);
    if (fontSize <= 0) fontSize = 11;
    if (p.headingLevel > 0) fontSize = fontSize * 1.15;
    final width = availableWidth - p.indentLeftPt;
    final usable = width < 40 ? 40.0 : width;
    final charsPerLine = usable / (fontSize * 0.5);

    var lines = 0;
    for (final run in p.runs) {
      if (run.isImage) {
        final imageLines =
            (run.imageHeightPt / (fontSize * 1.3)).ceil();
        lines += imageLines < 1 ? 1 : imageLines;
        continue;
      }
      if (run.text.isEmpty) continue;
      for (final segment in run.text.split('\n')) {
        if (segment.isEmpty) {
          lines += 1;
          continue;
        }
        final needed = (segment.length / charsPerLine).ceil();
        lines += needed < 1 ? 1 : needed;
      }
    }
    if (lines == 0) lines = 1;
    return lines * fontSize * 1.3 + p.spaceBeforePt + p.spaceAfterPt;
  }
}
