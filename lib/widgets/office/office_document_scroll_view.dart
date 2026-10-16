import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/ooxml/docx_document.dart';
import '../../services/ooxml/ooxml_document.dart';
import '../../services/ooxml/xlsx_workbook.dart';
import '../document_zoom.dart';
import 'docx_page_view.dart';
import 'pptx_slide_view.dart';
import 'xlsx_sheet_view.dart';


/// How a document is presented.
enum OfficeViewMode {
  /// One page at a time — the default, and what keeps every student on the
  /// same page as the teacher.
  pages,

  /// Every page stacked in one continuous scroll, for reading a long document
  /// or skimming a deck.
  scroll,
}

/// Continuous view of an Office document: every page stacked and scrollable.
///
/// Scrolling still drives the session: the page nearest the top is reported
/// through [onPageChanged], so students stay in step with the teacher instead
/// of drifting off somewhere in the document.
class OfficeDocumentScrollView extends StatefulWidget {
  final OoxmlDocument document;
  final int page;
  final ValueChanged<int>? onPageChanged;

  /// Shared with the page view, so switching between page and scroll mode
  /// keeps the zoom the teacher already set.
  final DocumentZoom? zoom;

  const OfficeDocumentScrollView({
    super.key,
    required this.document,
    required this.page,
    this.onPageChanged,
    this.zoom,
  });

  @override
  State<OfficeDocumentScrollView> createState() =>
      _OfficeDocumentScrollViewState();
}

class _OfficeDocumentScrollViewState extends State<OfficeDocumentScrollView> {
  final ScrollController _controller = ScrollController();

  /// Used to turn a double tap into a point in this view's own coordinates.
  final GlobalKey _surface = GlobalKey();

  /// Where the last half of a double tap landed.
  Offset? _pendingTap;

  /// Whether the list's viewer is allowed to pan — only once the document is
  /// actually zoomed in and there is something to drag.
  ///
  /// This is deliberately *not* read straight off the transform inside build,
  /// or inside a ListenableBuilder on it. Rebuilding the viewer while the
  /// fingers are still on it calls its `didUpdateWidget`, which throws away
  /// the cached transform — and that cached transform *is* the gesture in
  /// flight. Rebuilding on every tick of a pinch is precisely how you make
  /// pinch stop working, so the flag only moves once the transform has been
  /// still long enough to say the gesture is over.
  bool _panning = false;
  Timer? _settle;

  /// Page this view last *reported*, so the teacher's own scrolling is not
  /// mistaken for an external page change.
  int _reported = 0;
  int _pendingJump = 0;
  double _pageHeightPt = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _reported = widget.page;
    widget.zoom?.transform.addListener(_onTransform);
  }

  @override
  void didUpdateWidget(covariant OfficeDocumentScrollView old) {
    super.didUpdateWidget(old);
    if (old.zoom != widget.zoom) {
      old.zoom?.transform.removeListener(_onTransform);
      _settle?.cancel();
      _panning = false;
      widget.zoom?.transform.addListener(_onTransform);
    }
    // A page change that did not come from our own scrolling — the arrows, a
    // late join — should bring that page into view.
    if (widget.page != old.page && widget.page != _reported) {
      _pendingJump = widget.page;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyJump());
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    widget.zoom?.transform.removeListener(_onTransform);
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Re-latches [_panning] once the transform has stopped moving.
  void _onTransform() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final zoom = widget.zoom;
      if (zoom == null) return;
      final next = zoom.transform.value.getMaxScaleOnAxis() > 1.01;
      if (next != _panning) setState(() => _panning = next);
    });
  }

  void _onScroll() {
    if (_pageHeightPt <= 0 || !_controller.hasClients) return;
    final page =
        (_controller.offset / _pageHeightPt).floor().clamp(1, widget.document.pageCount);
    if (page == _reported) return;
    _reported = page;
    widget.onPageChanged?.call(page);
  }

  void _applyJump() {
    if (_pendingJump == 0 || !_controller.hasClients || _pageHeightPt <= 0) {
      return;
    }
    final target = (_pendingJump - 1) * _pageHeightPt;
    _pendingJump = 0;
    _controller.jumpTo(target.clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    ));
  }

  /// Aspect ratio (width / height) of one page, in points.
  double get _aspectRatio {
    switch (widget.document.format) {
      case OoxmlFormat.powerpoint:
        return _ratio(widget.document.deck?.slideWidthPt ?? 960,
            widget.document.deck?.slideHeightPt ?? 540);
      case OoxmlFormat.word:
        return _ratio(kPageWidthPt, kPageHeightPt);
      case OoxmlFormat.excel:
        return _ratio(kSheetPageWidthPt, kSheetPageRenderedHeightPt);
    }
  }

  static double _ratio(double width, double height) =>
      width <= 0 || height <= 0 ? 1.618 : width / height;

  @override
  Widget build(BuildContext context) {
    final total = widget.document.pageCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Pages are as wide as the viewport and keep their own proportions, so
        // the height is the same for every page and the maths stays simple.
        final width = constraints.maxWidth;
        final ratio = _aspectRatio;
        final height = width <= 0 ? 0.0 : width / ratio;
        _pageHeightPt = height;
        WidgetsBinding.instance.addPostFrameCallback((_) => _applyJump());
        final list = Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: total,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SizedBox(
                width: width,
                height: height,
                child: _page(index + 1),
              ),
            ),
          ),
        );
        final zoom = widget.zoom;
        // Scroll mode had no zoom at all, which made a dense Word page
        // impossible to read on a phone.
        if (zoom == null) return list;
        return Stack(
          children: [
            KeyedSubtree(
              key: _surface,
              child: InteractiveViewer(
                transformationController: zoom.transform,
                minScale: 1,
                maxScale: kZoomMax,
                // Off while the document fits, on once it does not. A scale
                // recogniser between the finger and a scrollable wins the
                // gesture arena every time, so with this on the list could
                // never be dragged and continuous mode looked frozen — the
                // pages were all there, you just could not reach them.
                panEnabled: _panning,
                boundaryMargin: const EdgeInsets.all(120),
                trackpadScrollCausesScale: true,
                scaleFactor: 200,
                child: GestureDetector(
                  // The list's viewer owns the gesture here, so the double tap
                  // that zooms into a spot has to be claimed at the same level.
                  // Each page's own canvas is inert in this mode; without this
                  // the gesture was simply gone.
                  onDoubleTapDown: (d) => _pendingTap = d.globalPosition,
                  onDoubleTap: () {
                    final tap = _pendingTap;
                    _pendingTap = null;
                    if (tap == null) return;
                    final box =
                        _surface.currentContext?.findRenderObject() as RenderBox?;
                    if (box == null) return;
                    zoom.toggleZoomAt(box.globalToLocal(tap), box.size);
                  },
                  child: list,
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: DocumentZoomBar(target: zoom.target),
            ),
          ],
        );
      },
    );
  }

  /// One page of the document, whatever format it is.
  ///
  /// Every page is handed `interactive: false`. The viewer around the list owns
  /// the gesture; a page that also handled it would put a second scale
  /// recogniser in the way and stop the list scrolling all over again.
  Widget _page(int page) {
    final document = widget.document;
    switch (document.format) {
      case OoxmlFormat.powerpoint:
        final deck = document.deck;
        if (deck == null) return const SizedBox.shrink();
        return PptxSlideView(deck: deck, page: page, interactive: false);
      case OoxmlFormat.word:
        final word = document.word;
        if (word == null) return const SizedBox.shrink();
        return DocxPageView(document: word, page: page, interactive: false);
      case OoxmlFormat.excel:
        final book = document.workbook;
        if (book == null) return const SizedBox.shrink();
        final located = book.excelPage(page);
        if (located == null) return const SizedBox.shrink();
        return XlsxSheetView(
          sheet: located.sheet,
          page: located.pageInSheet,
          firstRowNumber: (located.pageInSheet - 1) * kRowsPerSheetPage + 1,
          interactive: false,
        );
    }
  }
}
