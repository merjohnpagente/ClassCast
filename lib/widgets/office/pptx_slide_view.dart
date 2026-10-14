import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/ooxml/pptx_deck.dart';
import 'office_canvas.dart';

/// Draws one PowerPoint slide on the shared [OfficeCanvas].
///
/// Shape positions are already in points, so this is a straight mapping onto
/// the canvas: the same slide always lands in the same place.
class PptxSlideView extends StatelessWidget {
  final PptxDeck deck;
  final int page;

  const PptxSlideView({
    super.key,
    required this.deck,
    required this.page,
  });

  @override
  Widget build(BuildContext context) {
    final slides = deck.slides;
    if (slides.isEmpty) {
      return OfficeCanvas(
        widthPt: deck.slideWidthPt,
        heightPt: deck.slideHeightPt,
        child: const Center(child: Text('This deck has no slides.')),
      );
    }
    final index = page.clamp(1, slides.length).toInt() - 1;
    final slide = slides[index];

    return OfficeCanvas(
      widthPt: deck.slideWidthPt,
      heightPt: deck.slideHeightPt,
      background: Color(slide.background),
      child: Stack(
        children: [
          for (final shape in slide.shapes)
            if (shape.width > 0.5 && shape.height > 0.5)
              _positioned(shape),
        ],
      ),
    );
  }

  Widget _positioned(PptxShape shape) {
    Widget child = switch (shape.type) {
      PptxShapeType.picture => _picture(shape),
      PptxShapeType.table => _table(shape),
      PptxShapeType.box => _box(shape),
    };
    if (shape.rotationDegrees != 0) {
      child = Transform.rotate(
        angle: shape.rotationDegrees * math.pi / 180,
        child: child,
      );
    }
    return Positioned(
      left: shape.x,
      top: shape.y,
      width: shape.width,
      height: shape.height,
      child: child,
    );
  }

  Widget _picture(PptxShape shape) {
    final data = shape.image;
    if (data == null) return const SizedBox.shrink();
    return Image.memory(
      data,
      fit: BoxFit.fill,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image_outlined, size: 24),
    );
  }

  Widget _box(PptxShape shape) {
    final fill = shape.fill;
    return Container(
      decoration: BoxDecoration(
        color: fill == null ? null : argbWithOpacity(fill, shape.fillOpacity),
        shape: shape.ellipse ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: shape.roundRect
            ? BorderRadius.circular(math.min(shape.width, shape.height) / 6)
            : null,
      ),
      child: shape.text == null ? null : _textBox(shape.text!),
    );
  }

  Widget _textBox(PptxTextBox box) {
    return Padding(
      padding: EdgeInsets.only(
        left: box.insetLeftPt,
        top: box.insetTopPt,
        right: box.insetRightPt,
        bottom: box.insetBottomPt,
      ),
      child: Column(
        mainAxisAlignment: switch (box.anchor) {
          PptxVerticalAlign.top => MainAxisAlignment.start,
          PptxVerticalAlign.middle => MainAxisAlignment.center,
          PptxVerticalAlign.bottom => MainAxisAlignment.end,
        },
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final paragraph in box.paragraphs) _paragraph(paragraph),
        ],
      ),
    );
  }

  Widget _paragraph(PptxParagraph paragraph) {
    final base = paragraph.runs.isEmpty
        ? const PptxRun(text: '', fontSizePt: 18)
        : paragraph.runs.first;
    final spans = <InlineSpan>[];
    if (paragraph.bullet.isNotEmpty) {
      spans.add(TextSpan(
        text: '${paragraph.bullet}  ',
        style: TextStyle(
          color: Color(base.color),
          fontSize: base.fontSizePt,
          fontWeight: FontWeight.w400,
        ),
      ));
    }
    for (final run in paragraph.runs) {
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

    return Padding(
      padding: EdgeInsets.only(
        top: paragraph.spaceBeforePt,
        bottom: paragraph.spaceAfterPt,
        left: paragraph.indentLeftPt,
      ),
      child: Text.rich(
        TextSpan(children: spans),
        textAlign: switch (paragraph.align) {
          PptxTextAlign.left => TextAlign.left,
          PptxTextAlign.center => TextAlign.center,
          PptxTextAlign.right => TextAlign.right,
          PptxTextAlign.justify => TextAlign.justify,
        },
        style: TextStyle(
          fontSize: base.fontSizePt,
          height: paragraph.lineHeight,
          fontWeight: paragraph.isTitle ? FontWeight.w700 : null,
          // Office decks are laid out on a fixed page; clipping keeps a long
          // paragraph from painting over the rest of the slide.
          overflow: TextOverflow.clip,
        ),
        softWrap: true,
      ),
    );
  }

  Widget _table(PptxShape shape) {
    final table = shape.table;
    if (table == null) return const SizedBox.shrink();
    final rows = table.rows;
    if (rows.isEmpty) return const SizedBox.shrink();

    // The grid columns are in the frame's own units; scale them to the frame
    // the shape actually occupies.
    var gridTotal = 0.0;
    for (final width in table.columnWidthsPt) {
      gridTotal += width;
    }
    final scale = gridTotal > 0 ? shape.width / gridTotal : 1.0;
    final rowHeight = shape.height / rows.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          SizedBox(
            height: rowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _rowCells(table, row, scale, rowHeight),
            ),
          ),
      ],
    );
  }

  /// One widget per cell. The column cursor advances by each cell's span, so a
  /// merged cell takes the width of the columns it covers.
  List<Widget> _rowCells(
    PptxTable table,
    List<PptxTableCell> row,
    double scale,
    double rowHeight,
  ) {
    final out = <Widget>[];
    var column = 0;
    while (column < row.length) {
      final cell = row[column];
      final span = cell.colSpan < 1 ? 1 : cell.colSpan;
      var width = 0.0;
      for (var i = 0; i < span; i++) {
        final index = column + i;
        width += index < table.columnWidthsPt.length
            ? table.columnWidthsPt[index]
            : 60;
      }
      out.add(_tableCell(cell, width * scale, rowHeight));
      column += span;
    }
    return out;
  }

  Widget _tableCell(PptxTableCell cell, double width, double height) {
    return Container(
      width: width > 0 ? width : null,
      height: height,
      decoration: BoxDecoration(
        color: cell.fill == null
            ? null
            : argbWithOpacity(cell.fill!, cell.fillOpacity),
        border: Border.all(color: const Color(0x33000000), width: 0.75),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: cell.text == null
          ? null
          : _textBox(
              PptxTextBox(
                paragraphs: cell.text!.paragraphs,
                anchor: PptxVerticalAlign.middle,
                insetLeftPt: 2,
                insetTopPt: 1,
                insetRightPt: 2,
                insetBottomPt: 1,
              ),
            ),
    );
  }
}
