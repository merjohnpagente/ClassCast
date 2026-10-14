import 'package:flutter/material.dart';

import '../../services/ooxml/xlsx_workbook.dart';
import 'office_canvas.dart';

/// Height of one rendered sheet page, in points. The scroll view needs the
/// same number the canvas uses, or the page maths drifts and scrolling jumps.
const double kSheetPageRenderedHeightPt =
    kRowsPerSheetPage * kSheetRowHeightPt + kSheetRowHeightPt + 22;

/// Draws one printed page of a spreadsheet on the shared [OfficeCanvas].
///
/// Rows are cut into fixed-size pages (see [kRowsPerSheetPage]) so the page
/// number the teacher syncs matches what every student prints on screen.
class XlsxSheetView extends StatelessWidget {
  final XlsxSheet sheet;
  final int page;
  final int firstRowNumber;

  const XlsxSheetView({
    super.key,
    required this.sheet,
    required this.page,
    required this.firstRowNumber,
  });

  @override
  Widget build(BuildContext context) {
    final rows = sheet.rowsOfPage(page);
    final headerHeight = kSheetRowHeightPt;

    return OfficeCanvas(
      widthPt: kSheetPageWidthPt,
      heightPt: kSheetPageRenderedHeightPt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(headerHeight),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows.length; i++)
                  SizedBox(
                    height: kSheetRowHeightPt,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _rowHeader(firstRowNumber + i),
                        ..._layoutRow(rows[i]),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  /// One widget per visible column, honouring merged cell widths.
  List<Widget> _layoutRow(List<XlsxCell> row) {
    final out = <Widget>[];
    var column = 0;
    while (column < sheet.columnCount) {
      final cell = column < row.length ? row[column] : const XlsxCell(text: '');
      final span = cell.colSpan < 1 ? 1 : cell.colSpan;
      var width = 0.0;
      for (var i = 0; i < span && column + i < sheet.columnCount; i++) {
        width += _columnWidth(column + i);
      }
      out.add(_cell(cell, width));
      column += span;
    }
    return out;
  }

  double _columnWidth(int index) {
    if (index < 0 || index >= sheet.columnWidthsPt.length) return 64;
    final width = sheet.columnWidthsPt[index];
    return width <= 0 ? 64 : width;
  }

  Widget _header(double height) {
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 34,
            alignment: Alignment.center,
            decoration: _chrome,
            child: Text(
              sheet.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3E4A63),
              ),
            ),
          ),
          for (var c = 0; c < sheet.columnCount; c++)
            Container(
              width: _columnWidth(c),
              alignment: Alignment.center,
              decoration: _chrome,
              child: Text(
                _columnLetter(c),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7C879D),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rowHeader(int rowNumber) {
    return Container(
      width: 34,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 3),
      decoration: _chrome,
      child: Text(
        '$rowNumber',
        style: const TextStyle(fontSize: 9, color: Color(0xFF7C879D)),
      ),
    );
  }

  Widget _cell(XlsxCell cell, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: switch (cell.align) {
        XlsxAlign.left => Alignment.centerLeft,
        XlsxAlign.center => Alignment.center,
        XlsxAlign.right => Alignment.centerRight,
      },
      decoration: BoxDecoration(
        color: cell.fill == null ? null : Color(cell.fill!),
        border: const Border(
          right: BorderSide(color: Color(0x1F000000), width: 0.5),
          bottom: BorderSide(color: Color(0x1F000000), width: 0.5),
        ),
      ),
      child: Text(
        cell.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: cell.fontSizePt,
          fontWeight: cell.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: cell.italic ? FontStyle.italic : FontStyle.normal,
          color: Color(cell.color),
        ),
      ),
    );
  }

  Widget _footer() {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Page $page of ${sheet.pageCount} · ${sheet.rowCount} rows · '
              '${sheet.columnCount} columns',
              style: const TextStyle(fontSize: 9, color: Color(0xFF7C879D)),
            ),
          ),
        ],
      ),
    );
  }

  static const BoxDecoration _chrome = BoxDecoration(
    color: Color(0xFFF6F8FC),
    border: Border(
      right: BorderSide(color: Color(0x1F000000), width: 0.5),
      bottom: BorderSide(color: Color(0x1F000000), width: 0.5),
    ),
  );


  static String _columnLetter(int index) {
    var value = index;
    final buffer = StringBuffer();
    while (value >= 0) {
      buffer.write(String.fromCharCode(65 + value % 26));
      value = value ~/ 26 - 1;
    }
    return buffer.toString().split('').reversed.join();
  }
}
