/// Offline PowerPoint (.pptx) reader.
///
/// A .pptx is a zip of XML, so the deck is parsed and drawn by the app itself —
/// no laptop, no LibreOffice, no conversion step. It is an *approximate*
/// renderer: text, pictures, boxes, groups and tables are drawn with their real
/// geometry and colours, while effects (shadows, gradients, SmartArt, charts,
/// animations) are intentionally not simulated. What the teacher sees is a
/// faithful-enough slide for classroom projection.
library;

import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'ooxml_package.dart';

/// One parsed slide deck. Slide coordinates are stored in **points** so the
/// renderer can paint a fixed logical canvas and scale it to any screen.
class PptxDeck {
  final double slideWidthPt;
  final double slideHeightPt;
  final List<PptxSlide> slides;

  const PptxDeck({
    required this.slideWidthPt,
    required this.slideHeightPt,
    required this.slides,
  });

  int get slideCount => slides.length;

  /// Parses deck bytes. Returns null when this is not a readable .pptx.
  static PptxDeck? parse(Uint8List bytes) {
    final pkg = OoxmlPackage.tryOpen(bytes);
    if (pkg == null || !pkg.hasSlides) return null;
    try {
      return _PptxReader(pkg).read();
    } catch (_) {
      // A malformed deck must not crash the presentation screen: the caller
      // falls back to an honest "cannot open" panel.
      return null;
    }
  }
}

class PptxSlide {
  final int background;
  final List<PptxShape> shapes;

  const PptxSlide({required this.background, required this.shapes});

  /// Text of the title placeholder, or '' when the slide has none. Useful as a
  /// window/screen label while presenting.
  String get titleText {
    for (final shape in shapes) {
      final box = shape.text;
      if (box == null || box.paragraphs.isEmpty) continue;
      if (box.paragraphs.first.isTitle) return box.paragraphs.first.plainText;
    }
    return '';
  }
}

enum PptxShapeType { box, picture, table }

enum PptxVerticalAlign { top, middle, bottom }

enum PptxTextAlign { left, center, right, justify }

class PptxShape {
  final PptxShapeType type;
  final double x;
  final double y;
  final double width;
  final double height;

  /// Rotation in degrees, clockwise.
  final double rotationDegrees;

  final int? fill;
  final double fillOpacity;
  final bool roundRect;
  final bool ellipse;

  final PptxTextBox? text;
  final Uint8List? image;
  final PptxTable? table;

  const PptxShape({
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotationDegrees = 0,
    this.fill,
    this.fillOpacity = 1,
    this.roundRect = false,
    this.ellipse = false,
    this.text,
    this.image,
    this.table,
  });
}

class PptxTextBox {
  final List<PptxParagraph> paragraphs;
  final PptxVerticalAlign anchor;
  final double insetLeftPt;
  final double insetTopPt;
  final double insetRightPt;
  final double insetBottomPt;

  const PptxTextBox({
    required this.paragraphs,
    this.anchor = PptxVerticalAlign.top,
    this.insetLeftPt = 7.2,
    this.insetTopPt = 3.6,
    this.insetRightPt = 7.2,
    this.insetBottomPt = 3.6,
  });
}

class PptxParagraph {
  final List<PptxRun> runs;
  final int level;
  final PptxTextAlign align;
  final String bullet;
  final double indentLeftPt;
  final double firstLineIndentPt;
  final double spaceBeforePt;
  final double spaceAfterPt;
  final double lineHeight;
  final bool isTitle;

  const PptxParagraph({
    required this.runs,
    this.level = 0,
    this.align = PptxTextAlign.left,
    this.bullet = '',
    this.indentLeftPt = 0,
    this.firstLineIndentPt = 0,
    this.spaceBeforePt = 0,
    this.spaceAfterPt = 0,
    this.lineHeight = 1.2,
    this.isTitle = false,
  });

  String get plainText => runs.map((r) => r.text).join();
}

class PptxRun {
  final String text;
  final double fontSizePt;
  final bool bold;
  final bool italic;
  final bool underline;
  final int color;
  final String? typeface;

  const PptxRun({
    required this.text,
    required this.fontSizePt,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color = 0xFF000000,
    this.typeface,
  });
}

class PptxTable {
  final List<List<PptxTableCell>> rows;
  final List<double> columnWidthsPt;

  const PptxTable({required this.rows, required this.columnWidthsPt});
}

class PptxTableCell {
  final PptxTextBox? text;
  final int? fill;
  final double fillOpacity;
  final int colSpan;
  final int rowSpan;

  const PptxTableCell({
    this.text,
    this.fill,
    this.fillOpacity = 1,
    this.colSpan = 1,
    this.rowSpan = 1,
  });
}

/// Resolved shape box, in points.
class _Rect {
  final double x;
  final double y;
  final double w;
  final double h;

  const _Rect(this.x, this.y, this.w, this.h);
}

/// Affine mapping (scale + translation) applied to every descendant shape.
class _Transform {
  final double scaleX;
  final double scaleY;
  final double offsetX;
  final double offsetY;

  const _Transform(this.scaleX, this.scaleY, this.offsetX, this.offsetY);

  static const identity = _Transform(1, 1, 0, 0);

  double mapX(double x) => offsetX + x * scaleX;

  double mapY(double y) => offsetY + y * scaleY;

  

  /// Composition of this transform with a group's child-space mapping.
  _Transform thenGroup(_GroupTransform g) {
    return _Transform(
      scaleX * g.scaleX,
      scaleY * g.scaleY,
      offsetX + scaleX * (g.offsetX - g.childOffsetX),
      offsetY + scaleY * (g.offsetY - g.childOffsetY),
    );
  }
}

class _GroupTransform {
  final double offsetX;
  final double offsetY;
  final double extentX;
  final double extentY;
  final double childOffsetX;
  final double childOffsetY;
  final double childExtentX;
  final double childExtentY;

  const _GroupTransform({
    required this.offsetX,
    required this.offsetY,
    required this.extentX,
    required this.extentY,
    required this.childOffsetX,
    required this.childOffsetY,
    required this.childExtentX,
    required this.childExtentY,
  });

  double get scaleX => childExtentX <= 0 ? 1 : extentX / childExtentX;

  double get scaleY => childExtentY <= 0 ? 1 : extentY / childExtentY;
}

/// Text defaults inherited from the slide master for a placeholder type.
class _TextDefaults {
  final double fontSizePt;
  final bool bold;
  final int color;
  final String bullet;

  const _TextDefaults({
    required this.fontSizePt,
    required this.bold,
    required this.color,
    required this.bullet,
  });
}

/// A shape that inherits geometry from its layout/master.
class _Placeholder {
  final String type;
  final int index;

  const _Placeholder(this.type, this.index);

  String get key => '$type|$index';
}

/// Placeholder geometry collected from one part (a layout or the master).
class _PlaceholderTable {
  final Map<String, _Rect> byKey = {};
  final List<_Placeholder> order = [];
}

class _PptxReader {
  final OoxmlPackage _pkg;
  final Map<String, int> _scheme = {};

  // Per-slide inheritance state.
  final _PlaceholderTable _layout = _PlaceholderTable();
  final _PlaceholderTable _master = _PlaceholderTable();
  Map<String, _TextDefaults> _titleStyles = {};
  Map<String, _TextDefaults> _bodyStyles = {};
  Map<String, _TextDefaults> _otherStyles = {};
  int _masterBackground = 0xFFFFFFFF;

  _PptxReader(this._pkg);

  PptxDeck read() {
    final presentation = _pkg.xml('ppt/presentation.xml');
    if (presentation == null) {
      throw const FormatException('missing ppt/presentation.xml');
    }

    final size = findInDocument(presentation, 'sldSz');
    final cx = size == null ? 9144000 : intAttr(size, 'cx') ?? 9144000;
    final cy = size == null ? 6858000 : intAttr(size, 'cy') ?? 6858000;

    final rels = _pkg.relationships('ppt/presentation.xml');
    final slideParts = <String>[];
    final list = findInDocument(presentation, 'sldIdLst');
    if (list != null) {
      for (final sldId in childElements(list, 'sldId')) {
        final rid = relAttr(sldId, 'id');
        final target = rid == null ? null : rels[rid];
        if (target != null && _pkg.part(target) != null) slideParts.add(target);
      }
    }
    // Defensive fallback: a deck whose presentation part is odd but whose
    // slides are intact should still present.
    if (slideParts.isEmpty) {
      final found = _pkg.partNames
          .where((n) => n.startsWith('ppt/slides/slide') && n.endsWith('.xml'))
          .toList()
        ..sort();
      slideParts.addAll(found);
    }

    final slides = <PptxSlide>[];
    for (final part in slideParts) {
      slides.add(_readSlide(part));
    }

    return PptxDeck(
      slideWidthPt: points(cx),
      slideHeightPt: points(cy),
      slides: slides,
    );
  }

  PptxSlide _readSlide(String part) {
    final doc = _pkg.xml(part);
    if (doc == null) {
      return const PptxSlide(background: 0xFFFFFFFF, shapes: []);
    }
    _loadInheritance(part);

    final scope = findInDocument(doc, 'cSld');
    if (scope == null) {
      return const PptxSlide(background: 0xFFFFFFFF, shapes: []);
    }
    final background = _readBackground(scope);

    final tree = findDescendant(scope, 'spTree');
    final shapes = tree == null
        ? <PptxShape>[]
        : _readShapes(tree, _Transform.identity, part);

    return PptxSlide(background: background, shapes: shapes);
  }

  /// Resolves layout → master → theme for the slide at [slidePart].
  void _loadInheritance(String slidePart) {
    _layout.byKey.clear();
    _layout.order.clear();
    _master.byKey.clear();
    _master.order.clear();
    _titleStyles = {};
    _bodyStyles = {};
    _otherStyles = {};
    _masterBackground = 0xFFFFFFFF;
    _scheme.clear();

    final slideRels = _pkg.relationships(slidePart);
    String? layoutPart;
    for (final entry in slideRels.entries) {
      if (entry.value.contains('/slidelayouts/')) {
        layoutPart = entry.value;
        break;
      }
    }
    if (layoutPart == null || _pkg.xml(layoutPart) == null) return;

    _readPlaceholders(layoutPart, _layout);

    String? masterPart;
    for (final entry in _pkg.relationships(layoutPart).entries) {
      if (entry.value.contains('/slidemasters/')) {
        masterPart = entry.value;
        break;
      }
    }
    if (masterPart == null) return;
    final masterDoc = _pkg.xml(masterPart);
    if (masterDoc == null) return;

    _readPlaceholders(masterPart, _master);
    final masterScope = findInDocument(masterDoc, 'cSld');
    if (masterScope != null) _masterBackground = _readBackground(masterScope);

    // The theme has to be read before the text styles: master styles colour
    // text with scheme slots (`tx1`, `accent1`), which resolve against it.
    for (final entry in _pkg.relationships(masterPart).entries) {
      if (entry.value.contains('/theme/')) {
        _readTheme(entry.value);
        break;
      }
    }
    _readTextStyles(masterDoc);
  }

  void _readPlaceholders(String part, _PlaceholderTable sink) {
    final doc = _pkg.xml(part);
    if (doc == null) return;
    final tree = findInDocument(doc, 'spTree');
    if (tree == null) return;
    for (final sp in childElements(tree, 'sp')) {
      final ph = _placeholderOf(sp);
      if (ph == null) continue;
      final rect = _xfrmOf(sp);
      if (rect == null) continue;
      sink.byKey[ph.key] = rect;
      sink.order.add(ph);
    }
  }

  void _readTextStyles(XmlDocument masterDoc) {
    final txStyles = findInDocument(masterDoc, 'txStyles');
    if (txStyles == null) return;
    _titleStyles = _levelsOf(childElement(txStyles, 'titleStyle'));
    _bodyStyles = _levelsOf(childElement(txStyles, 'bodyStyle'));
    _otherStyles = _levelsOf(childElement(txStyles, 'otherStyle'));
  }

  Map<String, _TextDefaults> _levelsOf(XmlElement? styleRoot) {
    final out = <String, _TextDefaults>{};
    if (styleRoot == null) return out;
    for (var level = 1; level <= 9; level++) {
      final lvl = childElement(styleRoot, 'lvl${level}pPr');
      if (lvl == null) continue;
      final defRPr = childElement(lvl, 'defRPr');
      final size = intAttr(defRPr, 'sz');
      final color = colorFrom(defRPr, _scheme);
      out['$level'] = _TextDefaults(
        fontSizePt: (size ?? 1800) / 100,
        bold: defRPr?.getAttribute('b') == '1',
        color: color.opacity == 0 ? 0xFF000000 : color.argb,
        bullet: _bulletOf(lvl) ?? '',
      );
    }
    return out;
  }

  void _readTheme(String part) {
    final doc = _pkg.xml(part);
    if (doc == null) return;
    final scheme = findInDocument(doc, 'clrScheme');
    final map = <String, int>{
      'dk1': 0x000000,
      'lt1': 0xFFFFFF,
      'dk2': 0x1F497D,
      'lt2': 0xEEECE1,
      'accent1': 0x4F81BD,
      'accent2': 0xC0504D,
      'accent3': 0x9BBB59,
      'accent4': 0x8064A2,
      'accent5': 0x4BACC6,
      'accent6': 0xF79646,
      'hlink': 0x0000FF,
      'folhlink': 0x800080,
      // DrawingML aliases used by fills and text.
      'tx1': 0x000000,
      'bg1': 0xFFFFFF,
      'tx2': 0x1F497D,
      'bg2': 0xEEECE1,
    };
    if (scheme != null) {
      for (final slot in const [
        'dk1',
        'lt1',
        'dk2',
        'lt2',
        'accent1',
        'accent2',
        'accent3',
        'accent4',
        'accent5',
        'accent6',
        'hlink',
        'folHlink',
      ]) {
        final holder = childElement(scheme, slot);
        if (holder == null) continue;
        final resolved = _themeSlotColor(holder);
        if (resolved != null) map[slot.toLowerCase()] = resolved;
      }
      // `lt1`/`dk1` are the physical colours behind the `bg1`/`tx1` aliases.
      map['bg1'] = map['lt1'] ?? 0xFFFFFF;
      map['tx1'] = map['dk1'] ?? 0x000000;
      map['bg2'] = map['lt2'] ?? map['bg1']!;
      map['tx2'] = map['dk2'] ?? map['tx1']!;
    }
    _scheme
      ..clear()
      ..addAll(map);
  }

  /// `<a:dk1><a:sysClr lastClr="000000"/></a:dk1>` and friends.
  int? _themeSlotColor(XmlElement holder) {
    final color = colorOf(holder, const {});
    if (color.opacity == 0) return null;
    return color.argb & 0xFFFFFF;
  }

  int _readBackground(XmlElement scope) {
    final bg = childElement(scope, 'bg');
    if (bg == null) return _masterBackground;
    final pr = childElement(bg, 'bgPr');
    if (pr != null) {
      final parsed = colorFrom(pr, _scheme);
      if (parsed.opacity > 0) return parsed.argb;
    }
    final ref = childElement(bg, 'bgRef');
    if (ref != null) {
      final idx = intAttr(ref, 'idx') ?? 0;
      // bgRef indexes the master's fill styles; decks in the wild use
      // 1001/1002/1003 for background1/text1/background2 in that order.
      const slots = ['lt1', 'dk1', 'lt2'];
      final slot = slots[(idx - 1001).clamp(0, slots.length - 1).toInt()];
      final rgb = _scheme[slot];
      if (rgb != null) return rgb | 0xFF000000;
    }
    return _masterBackground;
  }

  List<PptxShape> _readShapes(
      XmlElement tree, _Transform xform, String slidePart) {
    final out = <PptxShape>[];
    for (final node in tree.children.whereType<XmlElement>()) {
      switch (node.localName) {
        case 'sp':
          final shape = _readShape(node, xform);
          if (shape != null) out.add(shape);
          break;
        case 'pic':
          final shape = _readPicture(node, xform, slidePart);
          if (shape != null) out.add(shape);
          break;
        case 'graphicFrame':
          final shape = _readGraphicFrame(node, xform);
          if (shape != null) out.add(shape);
          break;
        case 'grpSp':
          out.addAll(_readGroup(node, xform, slidePart));
          break;
        default:
          // cxnSp (connectors) and mc:AlternateContent wrappers are skipped.
          break;
      }
    }
    return out;
  }

  List<PptxShape> _readGroup(
      XmlElement group, _Transform parent, String slidePart) {
    final grpPr = childElement(group, 'grpSpPr');
    final xfrm = grpPr == null ? null : childElement(grpPr, 'xfrm');
    if (xfrm == null) return const [];
    final off = childElement(xfrm, 'off');
    final ext = childElement(xfrm, 'ext');
    final chOff = childElement(xfrm, 'chOff');
    final chExt = childElement(xfrm, 'chExt');
    if (off == null || ext == null || chOff == null || chExt == null) {
      return const [];
    }
    final g = _GroupTransform(
      offsetX: pointsAttr(off, 'x'),
      offsetY: pointsAttr(off, 'y'),
      extentX: pointsAttr(ext, 'cx'),
      extentY: pointsAttr(ext, 'cy'),
      childOffsetX: pointsAttr(chOff, 'x'),
      childOffsetY: pointsAttr(chOff, 'y'),
      childExtentX: pointsAttr(chExt, 'cx'),
      childExtentY: pointsAttr(chExt, 'cy'),
    );
    return _readShapes(group, parent.thenGroup(g), slidePart);
  }

  PptxShape? _readShape(XmlElement sp, _Transform xform) {
    final ph = _placeholderOf(sp);
    final spPr = childElement(sp, 'spPr');
    final xfrm = spPr == null ? null : childElement(spPr, 'xfrm');
    final rect = xfrm != null ? _rectOf(xfrm) : _inheritedRect(ph);
    if (rect == null) return null;

    final geom = spPr == null ? null : childElement(spPr, 'prstGeom');
    final prst = geom == null ? '' : (attr(geom, 'prst') ?? '');
    final fillColor = colorFrom(spPr, _scheme);
    final txBody = childElement(sp, 'txBody');
    final box = txBody == null ? null : _readTextBody(txBody, ph);

    // Nothing to draw: an empty placeholder or an invisible auto-shape.
    if (box == null && fillColor.opacity == 0) return null;

    return PptxShape(
      type: PptxShapeType.box,
      x: xform.mapX(rect.x),
      y: xform.mapY(rect.y),
      width: xform.scaleX * rect.w,
      height: xform.scaleY * rect.h,
      rotationDegrees: _rotationOf(xfrm),
      fill: fillColor.opacity == 0 ? null : fillColor.argb,
      fillOpacity: fillColor.opacity,
      roundRect: prst == 'roundRect' || prst == 'round2SameRect',
      ellipse: prst == 'ellipse',
      text: box,
    );
  }

  PptxShape? _readPicture(XmlElement pic, _Transform xform, String slidePart) {
    final spPr = childElement(pic, 'spPr');
    final xfrm = spPr == null ? null : childElement(spPr, 'xfrm');
    if (xfrm == null) return null;
    final rect = _rectOf(xfrm);
    final blipFill = childElement(pic, 'blipFill');
    final blip = blipFill == null ? null : findDescendant(blipFill, 'blip');
    final rid = blip == null ? null : relAttr(blip, 'embed');
    // `r:link` is a linked (not embedded) image: there are no bytes to show.
    final data = rid == null ? null : _pkg.relatedBytes(slidePart, rid);    if (data == null || data.isEmpty) return null;
    return PptxShape(
      type: PptxShapeType.picture,
      x: xform.mapX(rect.x),
      y: xform.mapY(rect.y),
      width: xform.scaleX * rect.w,
      height: xform.scaleY * rect.h,
      rotationDegrees: _rotationOf(xfrm),
      image: data,
    );
  }

  PptxShape? _readGraphicFrame(XmlElement frame, _Transform xform) {
    final xfrm = childElement(frame, 'xfrm');
    if (xfrm == null) return null;
    final rect = _rectOf(xfrm);
    final graphic = childElement(frame, 'graphic');
    final tbl = graphic == null ? null : findDescendant(graphic, 'tbl');
    if (tbl == null) return null;

    final widths = findDescendants(tbl, 'gridCol')
        .map((col) => pointsAttr(col, 'w'))
        .toList();

    final rows = <List<PptxTableCell>>[];
    for (final tr in childElements(tbl, 'tr')) {
      final row = <PptxTableCell>[];
      for (final tc in childElements(tr, 'tc')) {
        final tcPr = childElement(tc, 'tcPr');
        final fill = colorFrom(tcPr, _scheme);
        row.add(PptxTableCell(
          text: _readTextBodyOrNull(childElement(tc, 'txBody'), null),
          fill: fill.opacity == 0 ? null : fill.argb,
          fillOpacity: fill.opacity,
          colSpan: intAttrOr(tcPr, 'gridSpan', 1),
          rowSpan: intAttrOr(tcPr, 'rowSpan', 1),
        ));
      }
      if (row.isNotEmpty) rows.add(row);
    }
    if (rows.isEmpty) return null;

    return PptxShape(
      type: PptxShapeType.table,
      x: xform.mapX(rect.x),
      y: xform.mapY(rect.y),
      width: xform.scaleX * rect.w,
      height: xform.scaleY * rect.h,
      rotationDegrees: _rotationOf(xfrm),
      table: PptxTable(rows: rows, columnWidthsPt: widths),
    );
  }

  PptxTextBox? _readTextBodyOrNull(XmlElement? txBody, _Placeholder? ph) {
    if (txBody == null) return null;
    return _readTextBody(txBody, ph);
  }

  PptxTextBox? _readTextBody(XmlElement txBody, _Placeholder? ph) {
    final bodyPr = childElement(txBody, 'bodyPr');
    final autoFit = bodyPr == null ? null : childElement(bodyPr, 'normAutofit');
    final fontScale = autoFit == null
        ? 1.0
        : (intAttr(autoFit, 'fontScale') ?? 100000) / 100000;

    final anchor = switch (bodyPr == null ? null : attr(bodyPr, 'anchor')) {
      'ctr' => PptxVerticalAlign.middle,
      'b' => PptxVerticalAlign.bottom,
      _ => PptxVerticalAlign.top,
    };

    final paragraphs = <PptxParagraph>[];
    for (final p in childElements(txBody, 'p')) {
      final paragraph = _readParagraph(p, ph, fontScale);
      if (paragraph != null) paragraphs.add(paragraph);
    }
    if (paragraphs.isEmpty) return null;

    return PptxTextBox(
      paragraphs: paragraphs,
      anchor: anchor,
      insetLeftPt: pointsAttr(bodyPr, 'lIns', 7.2),
      insetTopPt: pointsAttr(bodyPr, 'tIns', 3.6),
      insetRightPt: pointsAttr(bodyPr, 'rIns', 7.2),
      insetBottomPt: pointsAttr(bodyPr, 'bIns', 3.6),
    );
  }

  PptxParagraph? _readParagraph(
      XmlElement p, _Placeholder? ph, double fontScale) {
    final pPr = childElement(p, 'pPr');
    final level = intAttrOr(pPr, 'lvl', 0);
    final defaults = _defaultsFor(ph, level);

    final runs = <PptxRun>[];
    for (final node in p.children.whereType<XmlElement>()) {
      if (node.localName != 'r' && node.localName != 'fld' &&
          node.localName != 'br') {
        continue;
      }
      final rPr = childElement(node, 'rPr');
      final size = rPr == null ? null : intAttr(rPr, 'sz');
      final color = colorFrom(rPr, _scheme);
      final boldAttr = rPr?.getAttribute('b');
      final underlineAttr = rPr?.getAttribute('u');
      final latin = rPr == null ? null : childElement(rPr, 'latin');

      if (node.localName == 'br') {
        runs.add(PptxRun(
          text: '\n',
          fontSizePt: defaults.fontSizePt * fontScale,
          color: defaults.color,
        ));
        continue;
      }

      final t = findDescendant(node, 't');
      final text = t?.innerText ?? '';
      if (text.isEmpty) continue;

      runs.add(PptxRun(
        text: text,
        // `sz` is in hundredths of a point.
        fontSizePt: (size == null ? defaults.fontSizePt * 100 : size.toDouble()) /
            100 *
            fontScale,
        bold: boldAttr == null ? defaults.bold : boldAttr == '1' || boldAttr == 'true',
        italic: rPr?.getAttribute('i') == '1',
        underline: underlineAttr != null && underlineAttr != 'none',
        color: color.opacity == 0 ? defaults.color : color.argb,
        typeface: latin == null ? null : attr(latin, 'typeface'),
      ));
    }
    if (runs.isEmpty) return null;

    var bullet = defaults.bullet;
    final explicit = _bulletOf(pPr);
    if (explicit != null) bullet = explicit;

    return PptxParagraph(
      runs: runs,
      level: level,
      align: _alignOf(pPr),
      bullet: bullet,
      indentLeftPt: pointsAttr(pPr, 'marL'),
      firstLineIndentPt: pointsAttr(pPr, 'indent'),
      spaceBeforePt: _spacingPoints(pPr, 'spcBef'),
      spaceAfterPt: _spacingPoints(pPr, 'spcAft'),
      lineHeight: _lineHeight(pPr),
      isTitle: ph?.type == 'title' || ph?.type == 'ctrTitle',
    );
  }

  static PptxTextAlign _alignOf(XmlElement? pPr) {
    switch (pPr == null ? null : attr(pPr, 'algn')) {
      case 'ctr':
        return PptxTextAlign.center;
      case 'r':
        return PptxTextAlign.right;
      case 'just':
        return PptxTextAlign.justify;
      default:
        return PptxTextAlign.left;
    }
  }

  double _spacingPoints(XmlElement? pPr, String which) {
    if (pPr == null) return 0;
    final holder = childElement(pPr, which);
    if (holder == null) return 0;
    final pts = childElement(holder, 'spcPts');
    final raw = pts == null ? intAttr(holder, 'val') : intAttr(pts, 'val');
    return (raw ?? 0) / 100;
  }

  double _lineHeight(XmlElement? pPr) {
    if (pPr == null) return 1.2;
    final holder = childElement(pPr, 'lnSpc');
    if (holder == null) return 1.2;
    final pct = childElement(holder, 'spcPct');
    final raw = pct == null ? intAttr(holder, 'val') : intAttr(pct, 'val');
    if (raw == null || raw <= 0) return 1.2;
    return (raw / 100000).clamp(0.5, 3.0).toDouble();
  }

  /// Bullet declared on the paragraph itself, or null when the paragraph does
  /// not override its level's bullet.
  String? _bulletOf(XmlElement? props) {
    if (props == null) return null;
    if (childElement(props, 'buNone') != null) return '';
    final buChar = childElement(props, 'buChar');
    return buChar == null ? null : (attr(buChar, 'char') ?? '');
  }

  _TextDefaults _defaultsFor(_Placeholder? ph, int level) {
    final type = ph?.type ?? '';
    final isTitle = type == 'title' || type == 'ctrTitle';
    final isSubtitle = type == 'subTitle';
    final Map<String, _TextDefaults> table;
    if (isTitle) {
      table = _titleStyles;
    } else if (type.isEmpty || type == 'body' || isSubtitle) {
      table = _bodyStyles.isEmpty ? _otherStyles : _bodyStyles;
    } else {
      table = _otherStyles;
    }

    final lvlKey = '${level + 1}';
    final fromMaster = table[lvlKey] ??
        (level == 0 ? table['1'] : null) ??
        (isTitle ? _titleStyles['1'] : null);
    if (fromMaster != null) return fromMaster;

    // No master style to inherit: fall back to readable classroom defaults.
    if (isTitle) {
      return const _TextDefaults(
        fontSizePt: 40,
        bold: true,
        color: 0xFF000000,
        bullet: '',
      );
    }
    if (isSubtitle) {
      return const _TextDefaults(
        fontSizePt: 24,
        bold: false,
        color: 0xFF404040,
        bullet: '',
      );
    }
    const byLevel = [24.0, 20.0, 18.0, 16.0];
    return _TextDefaults(
      fontSizePt: byLevel[level.clamp(0, byLevel.length - 1).toInt()],
      bold: false,
      color: 0xFF000000,
      bullet: level >= 1 ? '•' : '',
    );
  }

  _Rect? _inheritedRect(_Placeholder? ph) {
    if (ph == null) return null;
    final fromLayout = _matchPlaceholder(_layout, ph);
    if (fromLayout != null) return fromLayout;
    return _matchPlaceholder(_master, ph);
  }

  _Rect? _matchPlaceholder(_PlaceholderTable table, _Placeholder ph) {
    final exact = table.byKey[ph.key];
    if (exact != null) return exact;
    for (final candidate in table.order) {
      if (ph.type.isNotEmpty &&
          candidate.type == ph.type &&
          candidate.index == ph.index) {
        return table.byKey[candidate.key];
      }
    }
    for (final candidate in table.order) {
      if (ph.type.isNotEmpty && candidate.type == ph.type) {
        return table.byKey[candidate.key];
      }
    }
    for (final candidate in table.order) {
      if (candidate.index == ph.index) return table.byKey[candidate.key];
    }
    return null;
  }

  _Placeholder? _placeholderOf(XmlElement sp) {
    final nv = childElement(sp, 'nvSpPr');
    final nvPr = nv == null ? null : childElement(nv, 'nvPr');
    final ph = nvPr == null ? null : childElement(nvPr, 'ph');
    if (ph == null) return null;
    return _Placeholder(
      attr(ph, 'type') ?? 'body',
      intAttr(ph, 'idx') ?? 0,
    );
  }

  _Rect? _xfrmOf(XmlElement sp) {
    final spPr = childElement(sp, 'spPr');
    final xfrm = spPr == null ? null : childElement(spPr, 'xfrm');
    return xfrm == null ? null : _rectOf(xfrm);
  }

  _Rect _rectOf(XmlElement xfrm) {
    final off = childElement(xfrm, 'off');
    final ext = childElement(xfrm, 'ext');
    return _Rect(
      pointsAttr(off, 'x'),
      pointsAttr(off, 'y'),
      pointsAttr(ext, 'cx'),
      pointsAttr(ext, 'cy'),
    );
  }

  double _rotationOf(XmlElement? xfrm) {
    if (xfrm == null) return 0;
    return (intAttr(xfrm, 'rot') ?? 0) / 60000;
  }
}
