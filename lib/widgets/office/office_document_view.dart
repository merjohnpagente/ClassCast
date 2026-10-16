import 'package:flutter/material.dart';

import '../../services/ooxml/ooxml_document.dart';
import '../../services/ooxml/xlsx_workbook.dart';
import '../../theme/app_colors.dart';
import '../state_cards.dart';
import 'docx_page_view.dart';
import '../document_zoom.dart';
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

class _OfficeDocumentViewState extends State<OfficeDocumentView>
    with SingleTickerProviderStateMixin {
  Future<OoxmlDocument?>? _pending;

  /// The document, when it is already parsed and can be drawn this frame.
  ///
  /// A cache hit used to go through a Future anyway, and a FutureBuilder starts
  /// every future at `ConnectionState.none` — so a deck already sitting in
  /// memory still flashed a spinner, and a fresh `CircularProgressIndicator`
  /// with its own AnimationController, for one frame on *every* page turn. A
  /// teacher holding the arrow key watched it strobe. Anything already parsed
  /// is taken synchronously instead.
  OoxmlDocument? _ready;

  int _reported = 0;

  /// Owned here, above the pages, because each page used to have its own
  /// transform: zooming into a diagram and then turning the page lost it.
  late final DocumentZoom _zoom = DocumentZoom(this);

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OfficeDocumentView old) {
    super.didUpdateWidget(old);
    if (old.localPath != widget.localPath ||
        old.remoteUrl != widget.remoteUrl ||
        old.extension != widget.extension) {
      _reported = 0;
      _open();
    }
  }

  /// Resolves the document: the synchronous path when the parse is already
  /// cached, the future only when it actually has to read and parse something.
  void _open() {
    _ready = _peek();
    _pending = _ready == null ? _load() : null;
  }

  OoxmlDocument? _peek() {
    final key = OoxmlLoader.sourceKey(
      widget.extension,
      widget.localPath,
      widget.remoteUrl,
    );
    if (key == null) return null;
    return OoxmlLoader.instance.peek(key);
  }

  Future<OoxmlDocument?> _load() => OoxmlLoader.instance.load(
        extension: widget.extension,
        localPath: widget.localPath,
        remoteUrl: widget.remoteUrl,
      );

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    if (ready != null) return _page(ready);
    return FutureBuilder<OoxmlDocument?>(
      future: _pending,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return LoadingState(message: 'Opening ${widget.name}…');
        }
        if (snapshot.hasError) {
          return _failure(retry: true);
        }
        final document = snapshot.data;
        if (document == null) return _failure();
        return _page(document);
      },
    );
  }

  Widget _failure({bool retry = false}) => ErrorState(
        title: 'Could not open this file',
        message: _failureMessage(widget.extension),
        onRetry: retry
            ? () => setState(() {
                  _reported = 0;
                  _open();
                })
            : null,
      );

  /// Everything below here assumes the document is open and has pages.
  Widget _page(OoxmlDocument document) {
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
        zoom: _zoom,
        page: widget.page,
        onPageChanged: widget.onPageChanged,
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: _render(document)),
        Positioned(
          right: 10,
          bottom: 10,
          child: DocumentZoomBar(target: _zoom.target),
        ),
      ],
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
        return PptxSlideView(deck: deck, page: widget.page, zoom: _zoom);
      case OoxmlFormat.word:
        final word = document.word;
        if (word == null) return const SizedBox.shrink();
        return DocxPageView(document: word, page: widget.page, zoom: _zoom);
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
          zoom: _zoom,
          sheet: located.sheet,
          page: located.pageInSheet,
          firstRowNumber: (located.pageInSheet - 1) * kRowsPerSheetPage + 1,
        );
    }
  }

  static String _failureMessage(String extension) {
    // If the loader worked out what actually went wrong, say that. The generic
    // sentence it falls back to lists four unrelated causes and recommends
    // "re-save it" for all of them, and three of the four are fixed by doing
    // something else entirely.
    final reason = OoxmlLoader.lastFailure;
    if (reason != null && reason.isNotEmpty) return reason;
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
