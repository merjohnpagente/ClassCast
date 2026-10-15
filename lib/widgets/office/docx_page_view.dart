
import 'package:flutter/material.dart';

import '../../services/ooxml/docx_document.dart';
import 'office_canvas.dart';

/// Draws one page of a Word document on the shared [OfficeCanvas].
///
/// Page breaks come from [DocxDocument], which paginates against the same fixed
/// page box on every device — so the teacher's "page 2" is the student's
/// "page 2".
class DocxPageView extends StatelessWidget {
  final DocxDocument document;
  final int page;

  const DocxPageView({
    super.key,
    required this.document,
    required this.page,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = document.blocksOfPage(page);
    return OfficeCanvas(
      widthPt: kPageWidthPt,
      heightPt: kPageHeightPt,
      child: Padding(
        padding: const EdgeInsets.all(kPageMarginPt),
        child: blocks.isEmpty
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final block in blocks)
                    if (block.isTable)
                      _table(block.table!)
                    else
                      _paragraph(block.paragraph!),
                ],
              ),
      ),
    );
  }

  Widget _paragraph(DocxParagraph p) {
    final spans = <InlineSpan>[];
    for (final run in p.runs) {
      if (run.isImage) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Image.memory(
              run.image!,
              width: run.imageWidthPt > 0 ? run.imageWidthPt : 160,
              height: run.imageHeightPt > 0 ? run.imageHeightPt : 120,
              fit: BoxFit.contain,
              cacheWidth: kDecodeCapPx,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image_outlined, size: 24),
            ),
          ),
        ));
        continue;
      }
      if (run.text.isEmpty) continue;
      spans.add(TextSpan(
        text: run.text,
        style: TextStyle(
          color: Color(run.color),
          fontSize: run.fontSizePt,
          fontWeight: run.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
          decoration:
              run.underline ? TextDecoration.underline : TextDecoration.none,
          fontFamily: run.typeface,
        ),
      ));
    }
    if (spans.isEmpty) {
      // An empty paragraph still takes a line, exactly like Word.
      return SizedBox(height: (p.spaceBeforePt + p.spaceAfterPt) + 14);
    }

    final text = Text.rich(
      TextSpan(children: spans),
      textAlign: switch (p.align) {
        DocxAlign.left => TextAlign.left,
        DocxAlign.center => TextAlign.center,
        DocxAlign.right => TextAlign.right,
        DocxAlign.justify => TextAlign.justify,
      },
      style: const TextStyle(height: 1.3, overflow: TextOverflow.clip),
      softWrap: true,
    );

    // A hanging indent pulls the first line back over the bullet, so the
    // bullet marker is drawn outside the paragraph's own left indent.
    final hanging = -p.firstLineIndentPt > 0 ? -p.firstLineIndentPt : 0.0;

    return Padding(
      padding: EdgeInsets.only(
        top: p.spaceBeforePt,
        bottom: p.spaceAfterPt,
        left: p.indentLeftPt + hanging,
      ),
      child: p.bullet.isEmpty
          ? text
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    p.bullet,
                    style: TextStyle(
                      fontSize: p.runs.isEmpty ? 11 : p.runs.first.fontSizePt,
                      color: p.runs.isEmpty
                          ? const Color(0xFF000000)
                          : Color(p.runs.first.color),
                    ),
                  ),
                ),
                Expanded(child: text),
              ],
            ),
    );
  }

  Widget _table(DocxTable table) {
    final widths = table.columnWidthsPt;
    var total = 0.0;
    for (final width in widths) {
      total += width;
    }
    final scale = total > 0 ? (kPageContentWidthPt / total) : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in table.rows)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _rowCells(widths, row, scale),
              ),
            ),
        ],
      ),
    );
  }

  /// One widget per cell; a merged cell takes the width of the columns it
  /// covers so the grid stays square.
  List<Widget> _rowCells(
    List<double> widths,
    List<DocxTableCell> row,
    double scale,
  ) {
    final out = <Widget>[];
    var column = 0;
    while (column < row.length) {
      final cell = row[column];
      final span = cell.colSpan < 1 ? 1 : cell.colSpan;
      var width = 0.0;
      for (var i = 0; i < span; i++) {
        final index = column + i;
        width += index < widths.length ? widths[index] : 60;
      }
      out.add(_cell(cell, (width == 0 ? span * 60 : width) * scale));
      column += span;
    }
    return out;
  }

  Widget _cell(DocxTableCell cell, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: cell.fill == 0x00000000 ? null : Color(cell.fill),
        border: Border.all(color: const Color(0x22000000)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final paragraph in cell.paragraphs) _paragraph(paragraph),
        ],
      ),
    );
  }
}
