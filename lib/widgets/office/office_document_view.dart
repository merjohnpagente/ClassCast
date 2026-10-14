import 'package:flutter/material.dart';

import '../../services/ooxml/ooxml_document.dart';
import '../../services/ooxml/xlsx_workbook.dart';
import '../../theme/app_colors.dart';
import '../state_cards.dart';
import 'docx_page_view.dart';
import 'office_canvas.dart';
import 'office_document_scroll_view.dart';
import 'pptx_slide_view.dart';
import 'xlsx_sheet_view.dart';

/// Opens an Office file (pptx / docx / xlsx) and draws the requested page.
///
/// This is what makes PowerPoint, Word and Excel open straight from the phone:
/// no laptop, no LibreOffice, no conversion round-trip. The file is parsed once
/// and the parse is cached by [OoxmlLoader].
class OfficeDocumentView extends StatefulWidget {
  final String extension;
  final String name;
  final String? localPath;
  final String? remoteUrl;
  final int page;

  /// Reports how many pages the file actually has, so the session can sync the
  /// right total instead of an unknown one.
  final ValueChanged<int>? onPageCount;

  /// Page-by-page (default) or one continuous scroll. The teacher chooses; the
  /// class stays in step either way because scrolling reports the page.
  final OfficeViewMode viewMode;

  /// Reports the page the teacher is looking at while scrolling, so students
  /// follow along.
  final ValueChanged<int>? onPageChanged;

  const OfficeDocumentView({
    super.key,
    required this.extension,
    required this.name,
    required this.page,
    this.localPath,
    this.remoteUrl,
    this.onPageCount,
    this.viewMode = OfficeViewMode.pages,
    this.onPageChanged,
  });

  @override
  State<OfficeDocumentView> createState() => _OfficeDocumentViewState();
}

class _OfficeDocumentViewState extends State<OfficeDocumentView> {
  Future<OoxmlDocument?>? _pending;
  int _reported = 0;

  @override
  void initState() {
    super.initState();
    _pending = _load();
  }

  @override
  void didUpdateWidget(covariant OfficeDocumentView old) {
    super.didUpdateWidget(old);
    if (old.localPath != widget.localPath ||
        old.remoteUrl != widget.remoteUrl ||
        old.extension != widget.extension) {
      _reported = 0;
      _pending = _load();
    }
  }

  Future<OoxmlDocument?> _load() async {
    final key = OoxmlLoader.sourceKey(
      widget.extension,
      widget.localPath,
      widget.remoteUrl,
    );
    if (key != null) {
      final cached = OoxmlLoader.instance.peek(key);
      if (cached != null) return cached;
    }
    return OoxmlLoader.instance.load(
      extension: widget.extension,
      localPath: widget.localPath,
      remoteUrl: widget.remoteUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OoxmlDocument?>(
      future: _pending,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return LoadingState(message: 'Opening ${widget.name}…');
        }
        if (snapshot.hasError) {
          return ErrorState(
            title: 'Could not open this file',
            message: _failureMessage(widget.extension),
            retryLabel: 'Try again',
            onRetry: () => setState(() => _pending = _load()),
          );
        }
        final document = snapshot.data;
        if (document == null) {
          return ErrorState(
            title: 'Could not open this file',
            message: _failureMessage(widget.extension),
          );
        }
        if (document.pageCount <= 0) {
          return ErrorState(
            title: 'Nothing to show',
            message: '${widget.name} did not contain any '
                '${document.format == OoxmlFormat.powerpoint ? 'slides' : 'pages'}.',
          );
        }
        _reportPageCount(document.pageCount);
        if (widget.viewMode == OfficeViewMode.scroll) {
          return OfficeDocumentScrollView(
            document: document,
            page: widget.page,
            onPageChanged: widget.onPageChanged,
          );
        }
        return _render(document);
      },
    );
  }

  /// Fires the callback outside of build so listeners can safely setState.
  void _reportPageCount(int count) {
    final callback = widget.onPageCount;
    if (callback == null || count <= 0 || _reported == count) return;
    _reported = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback(count);
    });
  }

  Widget _render(OoxmlDocument document) {
    switch (document.format) {
      case OoxmlFormat.powerpoint:
        final deck = document.deck;
        if (deck == null) return const SizedBox.shrink();
        return PptxSlideView(deck: deck, page: widget.page);
      case OoxmlFormat.word:
        final word = document.word;
        if (word == null) return const SizedBox.shrink();
        return DocxPageView(document: word, page: widget.page);
      case OoxmlFormat.excel:
        final book = document.workbook;
        if (book == null) return const SizedBox.shrink();
        final located = book.excelPage(widget.page);
        if (located == null) {
          return OfficeCanvas(
            widthPt: kSheetPageWidthPt,
            heightPt: 200,
            child: const Center(
              child: Text(
                'This workbook has no visible sheets.',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          );
        }
        return XlsxSheetView(
          sheet: located.sheet,
          page: located.pageInSheet,
          firstRowNumber: (located.pageInSheet - 1) * kRowsPerSheetPage + 1,
        );
    }
  }

  static String _failureMessage(String extension) {
    if (OoxmlFileTypes.isLegacy(extension)) {
      final ext = extension.isEmpty ? 'pptx' : extension;
      return 'This is an old Office 97-2003 .$ext file, which is a completely '
          'different format from the modern one. Open it once and choose '
          '"Save as" the newer format (or a PDF), then share that file.';
    }
    return 'The app could not read this file. It may be damaged, password '
        'protected, or an unusual variant. Try re-saving it, or share a PDF.';
  }
}
