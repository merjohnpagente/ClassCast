import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:classcast_offline/services/ooxml/docx_document.dart';
import 'package:classcast_offline/services/ooxml/ooxml_document.dart';
import 'package:classcast_offline/services/ooxml/ooxml_package.dart';
import 'package:classcast_offline/services/ooxml/pptx_deck.dart';
import 'package:classcast_offline/services/ooxml/xlsx_workbook.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the offline Office readers.
///
/// The app opens .pptx / .docx / .xlsx itself (that is the whole point: no
/// laptop, no LibreOffice), so the parsers are tested against real zipped OOXML
/// containers built here, not against mocks.
void main() {
  group('PowerPoint', () {
    test('reads slide order, inherited geometry, text and pictures', () {
      final deck = PptxDeck.parse(_pptx());
      expect(deck, isNotNull);
      final parsed = deck!;

      // 12192000 x 6858000 EMU = the standard 16:9 widescreen slide.
      expect(parsed.slideWidthPt, 960);
      expect(parsed.slideHeightPt, 540);

      // sldIdLst lists slide2 first: presentation order is the list order, not
      // the file-name order. Getting this wrong shows students slide 2 as 1.
      expect(parsed.slideCount, 2);
      expect(parsed.slides.first.titleText, 'Second slide');

      final slide = parsed.slides.first;
      expect(slide.background, 0xFF102030);

      // The title has no xfrm of its own: it inherits the layout placeholder.
      final title = slide.shapes.firstWhere((s) => s.text != null);
      expect(title.x, 40);
      expect(title.y, 20);
      expect(title.width, 600);
      expect(title.height, 80);

      final titleParagraph = title.text!.paragraphs.first;
      expect(titleParagraph.plainText, 'Second slide');
      expect(titleParagraph.isTitle, isTrue);
      // Master txStyles drives the size (4000 = 40pt), and it stays bold.
      expect(titleParagraph.runs.first.fontSizePt, 40);
      expect(titleParagraph.runs.first.bold, isTrue);

      final picture =
          slide.shapes.firstWhere((s) => s.type == PptxShapeType.picture);
      expect(picture.image, isNotNull);
      expect(picture.image!.length, _pngBytes.length);
      expect(picture.width, 200);

      final box = slide.shapes
          .firstWhere((s) => s.type == PptxShapeType.box && s.fill != null);
      expect(box.fill, 0xFFFF0000);
      expect(box.text!.paragraphs.first.bullet, '•');
    });

    test('group shapes place their children through the group transform', () {
      final deck = PptxDeck.parse(_pptx())!;
      final grouped = deck.slides.first.shapes.firstWhere(
        (s) => s.text?.paragraphs.first.plainText.endsWith('-group') ?? false,
      );
      // Child space starts at (0,0); the group sits at 72pt/288pt and doubles
      // its children, so a 72pt box becomes a 144pt box 72pt to the right.
      expect(grouped.x, 72);
      expect(grouped.y, 288);
      expect(grouped.width, 144);
      expect(grouped.height, 144);
    });

    test('rejects files that are not OOXML packages', () {
      expect(PptxDeck.parse(Uint8List.fromList(utf8.encode('not a zip'))),
          isNull);
      // A zip that is not an Office document must not be presented as a deck.
      final empty = _zip({'readme.txt': 'hello'});
      expect(PptxDeck.parse(empty), isNull);
    });
  });

  group('Word', () {
    test('reads headings, bullets, tables and inline pictures', () {
      final document = DocxDocument.parse(_docx());
      expect(document, isNotNull);
      final parsed = document!;

      final paragraphs =
          parsed.blocks.where((b) => !b.isTable).map((b) => b.paragraph!).toList();
      expect(paragraphs.first.plainText, 'Lesson One');
      expect(paragraphs.first.headingLevel, 1);

      final bullet = paragraphs.firstWhere((p) => p.bullet.isNotEmpty);
      expect(bullet.bullet, '•');
      expect(bullet.plainText, 'First point');

      final table = parsed.blocks.firstWhere((b) => b.isTable).table!;
      expect(table.rows.length, 2);
      expect(table.rows.first.first.paragraphs.first.plainText, 'Name');
      expect(table.rows.first.first.colSpan, 2);

      final picture = paragraphs.firstWhere((p) => p.runs.any((r) => r.isImage));
      expect(picture.runs.first.image, isNotNull);
      expect(picture.runs.first.image!.length, _pngBytes.length);

      // Every block lands on exactly one page, and the pages cover the whole
      // document with no gaps or overlaps.
      final seen = <DocxBlock>[];
      for (var page = 1; page <= parsed.pageCount; page++) {
        seen.addAll(parsed.blocksOfPage(page));
      }
      expect(seen.length, parsed.blocks.length);
    });

    test('paginates deterministically for the same content', () {
      final first = DocxDocument.parse(_docx())!;
      final second = DocxDocument.parse(_docx())!;
      expect(first.pageCount, second.pageCount);
    });
  });

  group('Excel', () {
    test('reads sheets, shared strings, numbers and merges', () {
      final workbook = XlsxWorkbook.parse(_xlsx());
      expect(workbook, isNotNull);
      final parsed = workbook!;
      expect(parsed.sheetCount, 2);

      final sheet = parsed.sheets.first;
      expect(sheet.name, 'Scores');
      expect(sheet.columnCount, 3);
      expect(sheet.rows.first[0].text, 'Student');
      expect(sheet.rows[1][0].text, 'Ana');
      expect(sheet.rows[1][1].text, '95');
      expect(sheet.rows[1][1].bold, isTrue);
      // A1:B1 is merged, so the anchor keeps the full width.
      expect(sheet.rows.first[0].colSpan, 2);

      expect(parsed.sheets[1].name, 'Notes');
      expect(parsed.pageCount, sheet.pageCount + 1);
    });

    test('sheet pages map back to the right sheet', () {
      final workbook = XlsxWorkbook.parse(_xlsx())!;
      final first = workbook.excelPage(1)!;
      expect(first.sheet.name, 'Scores');
      expect(first.pageInSheet, 1);
      // Asking past the end stays on the last page instead of crashing.
      final last = workbook.excelPage(workbook.pageCount)!;
      expect(last.sheet.name, 'Notes');
    });

    test('renders a date serial with the authored format', () {
      final workbook = XlsxWorkbook.parse(_xlsx())!;
      final notes = workbook.sheets[1];
      // 45000 is 2023-03-15 in the 1900 date system.
      expect(notes.rows[1][1].text, '2023-03-15');
    });
  });

  group('format routing', () {
    test('the loader opens each modern Office format', () {
      expect(OoxmlLoader.parseBytes(extension: 'pptx', bytes: _pptx())!.format,
          OoxmlFormat.powerpoint);
      expect(OoxmlLoader.parseBytes(extension: 'docx', bytes: _docx())!.format,
          OoxmlFormat.word);
      expect(OoxmlLoader.parseBytes(extension: 'xlsx', bytes: _xlsx())!.format,
          OoxmlFormat.excel);
    });

    test('page counts drive what the session syncs', () {
      final deck = OoxmlLoader.parseBytes(extension: 'pptx', bytes: _pptx())!;
      expect(deck.pageCount, 2);
      final word = OoxmlLoader.parseBytes(extension: 'docx', bytes: _docx())!;
      expect(word.pageCount, greaterThanOrEqualTo(1));
      final book = OoxmlLoader.parseBytes(extension: 'xlsx', bytes: _xlsx())!;
      expect(book.pageCount, greaterThanOrEqualTo(2));
    });

    test('legacy binary Office files are reported as unopenable', () {
      // A real .ppt starts with the OLE compound-file signature; it is not a
      // zip, so nothing can render it and the UI must say so.
      final ole = Uint8List.fromList(
          List<int>.filled(512, 0).map((i) => i == 0 ? 0xD0 : 0).toList());
      expect(OoxmlLoader.parseBytes(extension: 'ppt', bytes: ole), isNull);
      expect(OoxmlFileTypes.isLegacy('ppt'), isTrue);
      expect(OoxmlFileTypes.isLegacy('pptx'), isFalse);
    });
  });

  group('package plumbing', () {
    test('relationships resolve relative targets', () {
      final pkg = OoxmlPackage.tryOpen(_pptx())!;
      expect(pkg.hasSlides, isTrue);
      final rels = pkg.relationships('ppt/slides/slide1.xml');
      expect(rels['rId1'], 'ppt/slidelayouts/slidelayout1.xml');
      expect(rels['rId3'], 'ppt/media/image1.png');
      expect(pkg.relatedBytes('ppt/slides/slide1.xml', 'rId3'),
          isNotNull);
    });

    test('a zip without [Content_Types].xml is not an OOXML package', () {
      expect(OoxmlPackage.tryOpen(_zip({'a.txt': 'x'})), isNull);
    });
  });

  // Every one of these used to reach the teacher as the same sentence about a
  // file being "damaged, password protected, or an unusual variant", and only
  // one of them is actually the file's fault. Each needs its own answer.
  group('failure reporting', () {
    String? reasonFor(Uint8List bytes) {
      String? reason;
      OoxmlPackage.tryOpen(bytes, onError: (r) => reason = r);
      return reason;
    }

    test('an OLE compound file is named as legacy or password protected', () {
      // The magic every Office 97-2003 .ppt/.doc/.xls begins with — and also
      // what a password-protected Office file is wrapped in.
      final ole = Uint8List.fromList([
        0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, //
        ...utf8.encode('rest of an OLE container'),
      ]);
      expect(OoxmlPackage.tryOpen(ole), isNull);
      final reason = reasonFor(ole)!;
      expect(reason, contains('97-2003'));
      expect(reason, contains('password protected'));
    });

    test('a truncated transfer says so instead of blaming the file', () {
      // Bytes that start like a zip but stop: what a hotspot transfer that
      // died half way leaves behind.
      final truncated = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]);
      expect(OoxmlPackage.tryOpen(truncated), isNull);
      expect(reasonFor(truncated), contains('transfer stopped'));
    });

    test('empty bytes are reported as empty', () {
      expect(OoxmlPackage.tryOpen(Uint8List(0)), isNull);
      expect(reasonFor(Uint8List(0)), contains('empty'));
    });

    test('a zip that is not an Office package says so', () {
      final reason = reasonFor(_zip({'a.txt': 'x'}))!;
      expect(reason, contains('no Office document'));
    });

    test('a deck that opens but has no presentation part is named', () {
      String? reason;
      PptxDeck.parse(
        _zip({
          '[Content_Types].xml': '<Types/>',
        }),
        onError: (r) => reason = r,
      );
      expect(reason, contains('ppt/presentation.xml'));
    });

    test('the loader keeps the reason so the screen can show it', () {
      // The path that matters: parseBytes reports, and the reason survives on
      // the loader for OfficeDocumentView to read.
      OoxmlLoader.parseBytes(
        extension: 'pptx',
        bytes: Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]),
      );
      expect(OoxmlLoader.parseBytes(
        extension: 'pptx',
        bytes: Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]),
      ), isNull);
    });
  });
}

// --- fixtures ---------------------------------------------------------------

final Uint8List _pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01,
]);

Uint8List _zip(Map<String, Object> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final value = entry.value;
    final bytes = value is String
        ? Uint8List.fromList(utf8.encode(value))
        : (value as Uint8List);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  return encoded is Uint8List ? encoded : Uint8List.fromList(encoded);
}

const _contentTypes = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
</Types>
''';

const _rootRels = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="ppt/presentation.xml"/>
</Relationships>
''';

Uint8List _pptx() {
  return _zip({
    '[Content_Types].xml': _contentTypes,
    '_rels/.rels': _rootRels,
    'ppt/presentation.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation
    xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:sldSz cx="12192000" cy="6858000"/>
  <p:sldIdLst>
    <p:sldId id="256" r:id="rId2"/>
    <p:sldId id="257" r:id="rId3"/>
  </p:sldIdLst>
</p:presentation>
''',
    'ppt/_rels/presentation.xml.rels': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="slideMasters/slideMaster1.xml"/>
  <Relationship Id="rId2" Target="slides/slide2.xml"/>
  <Relationship Id="rId3" Target="slides/slide1.xml"/>
</Relationships>
''',
    'ppt/slides/slide1.xml': _slideXml('First slide', 'F'),
    'ppt/slides/slide2.xml': _slideXml('Second slide', 'S'),
    'ppt/slides/_rels/slide1.xml.rels': _slideRels(),
    'ppt/slides/_rels/slide2.xml.rels': _slideRels(),
    'ppt/slideLayouts/slideLayout1.xml': _layoutXml(),
    'ppt/slideLayouts/_rels/slideLayout1.xml.rels': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>
''',
    'ppt/slideMasters/slideMaster1.xml': _masterXml(),
    'ppt/slideMasters/_rels/slideMaster1.xml.rels': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="../theme/theme1.xml"/>
</Relationships>
''',
    'ppt/theme/theme1.xml': _themeXml(),
    'ppt/media/image1.png': _pngBytes,
  });
}

String _slideXml(String title, String marker) => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
       xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:cSld>
    <p:bg>
      <p:bgPr><a:solidFill><a:srgbClr val="102030"/></a:solidFill></p:bgPr>
    </p:bg>
    <p:spTree>
      <p:sp>
        <p:nvSpPr>
          <p:nvPr><p:ph type="title"/></p:nvPr>
        </p:nvSpPr>
        <p:spPr/>
        <p:txBody>
          <a:bodyPr/>
          <a:p><a:r><a:rPr lang="en-US" dirty="0"/><a:t>$title</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
      <p:pic>
        <p:nvPicPr><p:cNvPr id="2" name="Picture"/><p:cNvPicPr/></p:nvPicPr>
        <p:blipFill>
          <a:blip r:embed="rId3"/>
          <a:stretch><a:fillRect/></a:stretch>
        </p:blipFill>
        <p:spPr>
          <a:xfrm><a:off x="500000" y="1000000"/><a:ext cx="2540000" cy="1905000"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
        </p:spPr>
      </p:pic>
      <p:sp>
        <p:nvSpPr><p:cNvPr id="3" name="Box"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="914400"/></a:xfrm>
          <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          <a:solidFill><a:srgbClr val="FF0000"/></a:solidFill>
        </p:spPr>
        <p:txBody>
          <a:bodyPr/>
          <a:p>
            <a:pPr lvl="1"/>
            <a:r><a:rPr lang="en-US"/><a:t>$marker</a:t></a:r>
          </a:p>
        </p:txBody>
      </p:sp>
      <p:grpSp>
        <p:nvGrpSpPr>
          <p:cNvPr id="4" name="Group"/>
          <p:cNvGrpSpPr/>
          <p:nvPr/>
        </p:nvGrpSpPr>
        <p:grpSpPr>
          <a:xfrm>
            <a:off x="914400" y="3657600"/>
            <a:ext cx="1828800" cy="1828800"/>
            <a:chOff x="0" y="0"/>
            <a:chExt cx="914400" cy="914400"/>
          </a:xfrm>
        </p:grpSpPr>
        <p:sp>
          <p:nvSpPr>
            <p:cNvPr id="5" name="InGroup"/>
            <p:cNvSpPr/>
            <p:nvPr/>
          </p:nvSpPr>
          <p:spPr>
            <a:xfrm><a:off x="0" y="0"/><a:ext cx="914400" cy="914400"/></a:xfrm>
            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
          </p:spPr>
          <p:txBody>
            <a:bodyPr/>
            <a:p><a:r><a:t>$marker-group</a:t></a:r></a:p>
          </p:txBody>
        </p:sp>
      </p:grpSp>
    </p:spTree>
  </p:cSld>
</p:sld>
''';

String _slideRels() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="../slideLayouts/slideLayout1.xml"/>
  <Relationship Id="rId3" Target="../media/image1.png"/>
</Relationships>
''';

String _layoutXml() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
              xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:sp>
        <p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
        <p:spPr>
          <a:xfrm><a:off x="508000" y="254000"/><a:ext cx="7620000" cy="1016000"/></a:xfrm>
        </p:spPr>
        <p:txBody><a:bodyPr/><a:p/></p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sldLayout>
''';

String _masterXml() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
              xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld><p:spTree/></p:cSld>
  <p:txStyles>
    <p:titleStyle>
      <a:lvl1pPr algn="ctr">
        <a:defRPr sz="4000" b="1">
          <a:solidFill><a:schemeClr val="tx1"/></a:solidFill>
        </a:defRPr>
      </a:lvl1pPr>
    </p:titleStyle>
    <p:bodyStyle>
      <a:lvl1pPr marL="342900" indent="-342900">
        <a:buFont typeface="Arial"/>
        <a:buChar char="•"/>
        <a:defRPr sz="2400"/>
      </a:lvl1pPr>
      <a:lvl2pPr>
        <a:buChar char="•"/>
        <a:defRPr sz="2000"/>
      </a:lvl2pPr>
    </p:bodyStyle>
  </p:txStyles>
</p:sldMaster>
''';

String _themeXml() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <a:clrScheme name="Office">
    <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
    <a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
    <a:dk2><a:srgbClr val="1F497D"/></a:dk2>
    <a:lt2><a:srgbClr val="EEECE1"/></a:lt2>
    <a:accent1><a:srgbClr val="4F81BD"/></a:accent1>
  </a:clrScheme>
</a:theme>
''';

Uint8List _docx() {
  return _zip({
    '[Content_Types].xml': _contentTypes,
    '_rels/.rels': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="word/document.xml"/>
</Relationships>
''',
    'word/document.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <w:body>
    <w:p>
      <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
      <w:r><w:t>Lesson One</w:t></w:r>
    </w:p>
    <w:p>
      <w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>
      <w:r><w:t>First point</w:t></w:r>
    </w:p>
    <w:p>
      <w:r>
        <w:drawing>
          <wp:inline>
            <wp:extent cx="1828800" cy="914400"/>
            <a:blip r:embed="rId9"/>
          </wp:inline>
        </w:drawing>
      </w:r>
    </w:p>
    <w:tbl>
      <w:tblGrid>
        <w:gridCol w:w="3000"/>
        <w:gridCol w:w="3000"/>
      </w:tblGrid>
      <w:tr>
        <w:tc>
          <w:tcPr><w:gridSpan w:val="2"/></w:tcPr>
          <w:p><w:r><w:t>Name</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:r><w:t>Ana</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>Bela</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>
  </w:body>
</w:document>
''',
    'word/_rels/document.xml.rels': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId9" Target="media/image1.png"/>
</Relationships>
''',
    'word/styles.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults>
    <w:rPrDefault><w:rPr><w:sz w:val="22"/></w:rPr></w:rPrDefault>
  </w:docDefaults>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/>
    <w:rPr><w:b/><w:sz w:val="32"/></w:rPr>
  </w:style>
</w:styles>
''',
    'word/numbering.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0">
    <w:lvl w:ilvl="0">
      <w:numFmt w:val="bullet"/>
      <w:lvlText w:val="&#8226;"/>
    </w:lvl>
  </w:abstractNum>
  <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
</w:numbering>
''',
    'word/media/image1.png': _pngBytes,
  });
}

Uint8List _xlsx() {
  return _zip({
    '[Content_Types].xml': _contentTypes,
    '_rels/.rels': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="xl/workbook.xml"/>
</Relationships>
''',
    'xl/workbook.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Scores" sheetId="1" r:id="rId1"/>
    <sheet name="Notes" sheetId="2" r:id="rId2"/>
  </sheets>
</workbook>
''',
    'xl/_rels/workbook.xml.rels': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Target="worksheets/sheet2.xml"/>
</Relationships>
''',
    'xl/worksheets/sheet1.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1">
      <c r="A1" t="s"><v>0</v></c>
      <c r="B1" t="s"><v>1</v></c>
      <c r="C1" t="s"><v>2</v></c>
    </row>
    <row r="2">
      <c r="A2" t="s"><v>3</v></c>
      <c r="B2" s="1"><v>95</v></c>
      <c r="C2"><v>88.5</v></c>
    </row>
  </sheetData>
  <mergeCells count="1"><mergeCell ref="A1:B1"/></mergeCells>
</worksheet>
''',
    'xl/worksheets/sheet2.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetData>
    <row r="1"><c r="A1" t="inlineStr"><is><t>Reviewed</t></is></c></row>
    <row r="2"><c r="A2" t="inlineStr"><is><t>Date</t></is></c><c r="B2" s="2"><v>45000</v></c></row>
  </sheetData>
</worksheet>
''',
    'xl/sharedStrings.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="4" uniqueCount="4">
  <si><t>Student</t></si>
  <si><t>Quiz</t></si>
  <si><t>Average</t></si>
  <si><t>Ana</t></si>
</sst>
''',
    'xl/styles.xml': '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/></font>
    <font><b/><sz val="11"/></font>
  </fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
  </fills>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0"/>
    <xf numFmtId="0" fontId="1" fillId="0" applyFont="1"/>
    <xf numFmtId="14" fontId="0" fillId="0" applyNumberFormat="1"/>
  </cellXfs>
</styleSheet>
''',
  });
}
