import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// EMU is the DrawingML unit: 914400 EMU = 1 inch = 72 pt.
const int kEmuPerInch = 914400;
const int kEmuPerPoint = 12700;

/// Word stores measurements in twips (1 pt = 20 twips).
const double kTwipsPerPoint = 20;

/// A colour resolved from an OOXML fill: 0xAARRGGBB plus a separate opacity.
class OoxmlColor {
  final int argb;
  final double opacity;

  const OoxmlColor(this.argb, [this.opacity = 1]);

  static const OoxmlColor none = OoxmlColor(0x00000000, 0);
}

/// An opened OOXML package (.pptx / .docx / .xlsx are all zip archives of XML).
///
/// Everything here is pure Dart on purpose: the same parser runs in unit tests,
/// on Android and in the browser, and it is what lets the app open Office files
/// without converting them on a laptop first.
class OoxmlPackage {
  OoxmlPackage._(this._parts);

  final Map<String, Uint8List> _parts;

  /// Opens a zip container. Returns null when the bytes are not a readable
  /// OOXML package (for example a legacy binary .ppt/.doc/.xls, which is an
  /// OLE compound file and not a zip).
  static OoxmlPackage? tryOpen(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }
    final parts = <String, Uint8List>{};
    try {
      for (final file in archive) {
        if (!file.isFile) continue;
        final name = _normalize(file.name);
        if (name.isEmpty) continue;
        parts[name] = file.content;
      }
    } catch (_) {
      return null;
    }
    // A real Office package always carries [Content_Types].xml.
    if (!parts.containsKey('[content_types].xml')) return null;
    return OoxmlPackage._(parts);
  }

  /// True when the package holds presentation slides.
  bool get hasSlides => _parts.containsKey('ppt/presentation.xml');

  /// True when the package holds a WordprocessingML main document.
  bool get hasWordDocument => _parts.containsKey('word/document.xml');

  /// True when the package holds a SpreadsheetML workbook.
  bool get hasWorkbook => _parts.containsKey('xl/workbook.xml');

  /// Case-insensitive part lookup, so a deck written by an older PowerPoint
  /// (which sometimes uppercases media names) still resolves.
  Uint8List? part(String name) {
    final key = _normalize(name);
    final direct = _parts[key];
    if (direct != null) return direct;
    for (final entry in _parts.entries) {
      if (entry.key.toLowerCase() == key) return entry.value;
    }
    return null;
  }

  /// Part names in the package (normalized, forward slashes).
  Iterable<String> get partNames => _parts.keys;

  /// UTF-8 text of a part, or null when the part is missing/undecodable.
  String? text(String name) {
    final bytes = part(name);
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// Parsed XML for a part, or null when it is absent or malformed.
  XmlDocument? xml(String name) {
    final raw = text(name);
    if (raw == null || raw.isEmpty) return null;
    try {
      return XmlDocument.parse(raw);
    } catch (_) {
      return null;
    }
  }

  /// `rId → part path` for the relationships of [partName].
  ///
  /// Targets are stored relative to the part, e.g. `../media/image1.png`,
  /// so they are resolved to package-absolute paths here once.
  Map<String, String> relationships(String partName) {
    final relsPath = _relsPathFor(partName);
    final doc = xml(relsPath);
    final out = <String, String>{};
    if (doc == null) return out;
    for (final rel in doc.findAllElements('Relationship')) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id == null || target == null || id.isEmpty || target.isEmpty) {
        continue;
      }
      // External links (Mode="External") are URLs, not package parts.
      if (rel.getAttribute('TargetMode') == 'External') continue;
      out[id] = _resolve(_normalize(partName), target);
    }
    return out;
  }

  /// Follows a relationship id from [partName] to its bytes.
  Uint8List? relatedBytes(String partName, String relationshipId) {
    final target = relationships(partName)[relationshipId];
    return target == null ? null : part(target);
  }

  static String _normalize(String name) {
    var n = name.trim().replaceAll('\\', '/');
    while (n.startsWith('/')) {
      n = n.substring(1);
    }
    // Some writers duplicate a leading "./".
    while (n.startsWith('./')) {
      n = n.substring(2);
    }
    return n.toLowerCase();
  }

  static String _relsPathFor(String partName) {
    final dir = p.dirname(partName);
    final base = p.basename(partName);
    final file = dir == '.' || dir.isEmpty
        ? '_rels/$base.rels'
        : '$dir/_rels/$base.rels';
    return file.toLowerCase();
  }

  /// Resolves [target] (relative to the folder of [fromPart]) to a package path.
  static String _resolve(String fromPart, String target) {
    if (target.startsWith('/')) return _normalize(target);
    final dir = p.dirname(fromPart);
    final joined = dir == '.' || dir.isEmpty ? target : '$dir/$target';
    return _normalize(p.normalize(joined));
  }

  /// Resolves a relationship target from [fromPart]. Exposed for the parsers,
  /// which need the *path* (slide layouts, master, theme) rather than bytes.
  static String resolveTarget(String fromPart, String target) =>
      _resolve(_normalize(fromPart), target);
}

// --- XML helpers -----------------------------------------------------------
//
// OOXML is namespaced, but prefix choice varies between producers (PowerPoint
// writes `a:`/`p:`, other tools write `a:`/`p:` too, yet relationships can be
// renamed). Matching on the *local* name keeps the parsers prefix-agnostic.

/// First direct child of [parent] whose local name is [localName].
XmlElement? childElement(XmlNode? parent, String localName) {
  if (parent == null) return null;
  for (final node in _childrenOf(parent)) {
    if (_localName(node) == localName) return node;
  }
  return null;
}

/// All direct children of [parent] whose local name is [localName].
List<XmlElement> childElements(XmlNode? parent, String localName) {
  if (parent == null) return const [];
  return _childrenOf(parent)
      .where((e) => _localName(e) == localName)
      .toList();
}

/// Children of [node], stepping into the root element of a document so that
/// `childElements(doc, 'sheet')` works the same as on an element.
Iterable<XmlElement> _childrenOf(XmlNode node) {
  if (node is XmlDocument) return node.rootElement.children.whereType<XmlElement>();
  return node.children.whereType<XmlElement>();
}

/// The elements a search starts from: for a document that is its root element,
/// so a part whose root *is* the element being looked for is still found.
Iterable<XmlElement> _searchRoots(XmlNode node) {
  if (node is XmlDocument) return <XmlElement>[node.rootElement];
  if (node is XmlElement) return <XmlElement>[node];
  return const <XmlElement>[];
}

/// Depth-first search for the first descendant with the given local name.
XmlElement? findDescendant(XmlNode parent, String localName) {
  for (final node in _searchRoots(parent)) {
    if (_localName(node) == localName) return node;
    final hit = _findBelow(node, localName);
    if (hit != null) return hit;
  }
  return null;
}

/// Search strictly below [parent] (no self-check), which is what keeps the
/// recursion from walking into itself forever.
XmlElement? _findBelow(XmlElement parent, String localName) {
  for (final node in _childrenOf(parent)) {
    if (_localName(node) == localName) return node;
    final hit = _findBelow(node, localName);
    if (hit != null) return hit;
  }
  return null;
}

/// Depth-first search for every descendant with the given local name.
List<XmlElement> findDescendants(XmlNode parent, String localName) {
  final out = <XmlElement>[];
  void walk(XmlElement scope) {
    for (final node in _childrenOf(scope)) {
      if (_localName(node) == localName) out.add(node);
      walk(node);
    }
  }

  for (final root in _searchRoots(parent)) {
    if (_localName(root) == localName) out.add(root);
    walk(root);
  }
  return out;
}

/// Document-wide search for the first element with the given local name.
XmlElement? findInDocument(XmlDocument doc, String localName) =>
    findDescendant(doc, localName);

/// Attribute lookup ignoring the namespace prefix (`r:id` is found as `id`).
String? attr(XmlElement? element, String localName) {
  if (element == null) return null;
  for (final a in element.attributes) {
    if (_localName(a) == localName) return a.value;
  }
  return null;
}

int? intAttr(XmlElement? element, String localName) =>
    int.tryParse(attr(element, localName) ?? '');

/// Relationship attribute lookup (`r:id`, `r:embed`, `r:link`).
///
/// Plain [attr] is not safe here: `<p:sldId id="256" r:id="rId2"/>` has *two*
/// attributes whose local name is `id`, and picking the wrong one loses the
/// slide reference entirely. The namespaced one wins.
String? relAttr(XmlElement? element, String localName) {
  if (element == null) return null;
  String? unqualified;
  for (final a in element.attributes) {
    if (a.localName != localName) continue;
    if (a.name.prefix == 'r') return a.value;
    if (a.name.prefix == null) unqualified ??= a.value;
  }
  return unqualified;
}

double? doubleAttr(XmlElement? element, String localName) =>
    double.tryParse(attr(element, localName) ?? '');

String _localName(XmlNode node) {
  if (node is XmlElement) return node.localName;
  if (node is XmlAttribute) return node.localName;
  return node.toString();
}

// --- value helpers ---------------------------------------------------------

/// Parses an integer, tolerating "1.5" style values from lenient producers.
double toDouble(String? raw, [double fallback = 0]) {
  if (raw == null) return fallback;
  return double.tryParse(raw.trim()) ?? fallback;
}

/// Resolves a colour from a fill container (`a:solidFill`, `a:bgPr`, `w:shd`).
///
/// [scheme] maps theme slots (`accent1`, `tx1`, `bg1`…) to 0xRRGGBB values so
/// theme-coloured shapes and text come out in the deck's own palette. A missing
/// or absent fill comes back as [OoxmlColor.none] (opacity 0), so callers can
/// write `color.opacity == 0` instead of juggling nulls.
///
/// Only *direct* children are inspected by default: a shape's `<a:ln>` also
/// contains a `solidFill`, and mistaking the outline colour for the fill paints
/// every outlined shape solid. Pass [deep] when the colour genuinely sits at an
/// unknown depth.
OoxmlColor colorFrom(
  XmlElement? fillParent,
  Map<String, int> scheme, {
  bool deep = false,
}) {
  if (fillParent == null) return OoxmlColor.none;
  // `<a:solidFill>` may be the given element itself, or a direct child of it.
  final XmlElement? fill;
  if (fillParent.localName == 'solidFill') {
    fill = fillParent;
  } else {
    fill = childElement(fillParent, 'solidFill');
  }
  final XmlElement? target =
      fill ?? (deep ? findDescendant(fillParent, 'solidFill') : null);
  return target == null ? OoxmlColor.none : colorOf(target, scheme);
}

/// Resolves a colour *element* (`a:srgbClr` / `a:schemeClr` / `a:sysClr`).
OoxmlColor colorOf(XmlElement fill, Map<String, int> scheme) {
  final srgb = childElement(fill, 'srgbClr');
  if (srgb != null) {
    final hex = (attr(srgb, 'val') ?? '').replaceAll('#', '');
    final rgb = hexRgb(hex);
    return rgb == null ? OoxmlColor.none : OoxmlColor(rgb | 0xFF000000, _alpha(srgb));
  }

  final schemeClr = childElement(fill, 'schemeClr');
  if (schemeClr != null) {
    final rgb = scheme[(attr(schemeClr, 'val') ?? '').toLowerCase()];
    if (rgb == null) return OoxmlColor.none;
    return OoxmlColor(rgb | 0xFF000000, _alpha(schemeClr));
  }

  final sys = childElement(fill, 'sysClr');
  if (sys != null) {
    final rgb = hexRgb(attr(sys, 'lastClr') ?? '');
    return rgb == null ? OoxmlColor.none : OoxmlColor(rgb | 0xFF000000, _alpha(sys));
  }

  return OoxmlColor.none;
}

/// Reads `<a:alpha val="60000"/>` as an opacity in 0..1.
double _alpha(XmlElement colorElement) {
  final alpha = childElement(colorElement, 'alpha');
  final raw = alpha == null ? null : intAttr(alpha, 'val');
  if (raw == null) return 1;
  return (raw / 100000).clamp(0.0, 1.0);
}

int? hexRgb(String hex) {
  if (hex.length != 6 && hex.length != 8) return null;
  final clean = hex.length == 8 ? hex.substring(2) : hex;
  return int.tryParse(clean, radix: 16);
}

/// Parses a `val`-style colour attribute (`w:color w:val="FF0000"`).
int? colorFromHexAttribute(String? hex) {
  if (hex == null) return null;
  final rgb = hexRgb(hex.trim());
  return rgb == null ? null : rgb | 0xFF000000;
}

/// Converts an OOXML measurement to points, with an optional fallback.
double points(num? emu, [double fallbackPt = 0]) {
  if (emu == null) return fallbackPt;
  return emu / kEmuPerPoint;
}

/// Reads a points value straight off an element attribute (EMU based).
double pointsAttr(XmlElement? element, String localName,
    [double fallbackPt = 0]) {
  if (element == null) return fallbackPt;
  return points(doubleAttr(element, localName), fallbackPt);
}

/// Reads an integer attribute, falling back when the element or value is absent.
int intAttrOr(XmlElement? element, String localName, int fallback) {
  if (element == null) return fallback;
  return intAttr(element, localName) ?? fallback;
}

/// Reads a count/span property written as a child element with a `val`
/// attribute, the way Word writes it: `<w:gridSpan w:val="2"/>`.
///
/// (DrawingML writes the same idea as a plain attribute, so those parsers use
/// [intAttrOr] instead.)
int countChild(XmlElement? properties, String localName, int fallback) =>
    intAttr(childElement(properties, localName), 'val') ?? fallback;
