import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/doc_types.dart';
import '../models/shared_document.dart';
import '../theme/app_colors.dart';
import '../utils/local_file.dart';
import 'document_zoom.dart';
import 'office/office_document_view.dart';
import 'office/office_document_scroll_view.dart';
import 'state_cards.dart';

/// Renders the real shared document.
///
/// - PDF  → Syncfusion viewer on the local file (teacher) or the host URL
///          (student), with page control driven by the teacher.
/// - PowerPoint / Word / Excel (.pptx / .docx / .xlsx) → opened by the app
///   itself and drawn on a fixed page canvas, so the teacher can present a
///   deck, a worksheet or a spreadsheet straight from the phone.
/// - Image / text → rendered directly.
/// - Anything else → an honest panel instead of a blank screen.
class DocumentViewer extends StatefulWidget {
  final SharedDocument doc;
  final PdfViewerController controller;

  /// Remote URL for students (served by the teacher host). When null the
  /// viewer falls back to the local file picked on this device.
  final String? remoteUrl;

  /// Page the teacher is on (1-based). Office documents draw exactly this
  /// page; PDFs use it to stay in sync with the session too.
  final int page;

  /// Reports how many pages an Office file really has, so the session can
  /// sync a real total.
  final ValueChanged<int>? onPageCount;

  /// Page-by-page or continuous scrolling. Only the teacher normally switches
  /// this; students follow the teacher's page either way.
  final OfficeViewMode viewMode;

  /// Reports the page being scrolled, so the session can follow along.
  final ValueChanged<int>? onPageChanged;

  /// When true, show the conversion panel instead of a preview.
  final bool showConversionPanel;

  const DocumentViewer({
    super.key,
    required this.doc,
    required this.controller,
    this.remoteUrl,
    this.page = 1,
    this.onPageCount,
    this.viewMode = OfficeViewMode.pages,
    this.onPageChanged,
    this.showConversionPanel = false,
  });

  @override
  State<DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<DocumentViewer>
    with SingleTickerProviderStateMixin {
  /// Zoom for the formats this widget draws itself. PDF zooms through
  /// Syncfusion and Office through the canvas, so only images land here.
  late final DocumentZoom _imageZoom = DocumentZoom(this);

  @override
  void dispose() {
    _imageZoom.dispose();
    super.dispose();
  }

  SharedDocument get doc => widget.doc;

  PdfViewerController get controller => widget.controller;

  String? get remoteUrl => widget.remoteUrl;

  int get page => widget.page;

  ValueChanged<int>? get onPageCount => widget.onPageCount;

  OfficeViewMode get viewMode => widget.viewMode;

  ValueChanged<int>? get onPageChanged => widget.onPageChanged;

  bool get showConversionPanel => widget.showConversionPanel;

  @override
  Widget build(BuildContext context) {
    final box = BoxDecoration(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.large),
      border: Border.all(color: AppColors.border),
    );

    if (showConversionPanel || _needsConversion(doc)) {
      return _ConversionPanel(doc: doc, box: box);
    }

    switch (doc.kind) {
      case DocKind.pdf:
        return _pdf(box);
      case DocKind.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: Container(
            decoration: box,
            child: _image(),
          ),
        );
      case DocKind.text:
        return _text(box);
      case DocKind.powerpoint:
      case DocKind.word:
      case DocKind.excel:
        return _office(box);
      case DocKind.unknown:
        return _ConversionPanel(doc: doc, box: box);
    }
  }

  bool _needsConversion(SharedDocument d) {
    final s = d.status;
    return s == DocStatus.needsConversion ||
        s == DocStatus.converting ||
        s == DocStatus.conversionFailed ||
        s == DocStatus.unsupported;
  }

  /// PowerPoint, Word and Excel are parsed and drawn in-app.
  Widget _office(BoxDecoration box) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: Container(
        decoration: box,
        child: OfficeDocumentView(
          extension: doc.extension,
          name: doc.name,
          localPath: doc.localPath,
          remoteUrl: remoteUrl,
          page: page,
          onPageCount: onPageCount,
          viewMode: viewMode,
          onPageChanged: onPageChanged,
        ),
      ),
    );
  }

  Widget _pdf(BoxDecoration box) {
    // Students fetch from the teacher host; the teacher renders the file it
    // picked directly. Never fall back to a bundled sample asset.
    if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Container(
          decoration: box,
          child: Stack(
            children: [
              Positioned.fill(
                child: SfPdfViewer.network(
                  remoteUrl!,
                  controller: controller,
                  canShowScrollHead: false,
                  // 3x was not enough to read fine print on a projector; the
                  // Office canvas has always allowed 6x.
                  maxZoomLevel: kZoomMax,
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: _PdfZoomBar(controller),
              ),
            ],
          ),
        ),
      );
    }
    final path = doc.localPath;
    if (path == null || path.isEmpty) {
      return _MissingFile(box: box, name: doc.name);
    }
    return _LocalFile<Uint8List>(
      path: path,
      load: localFileReadBytes,
      onMissing: _MissingFile(box: box, name: doc.name),
      builder: (context, bytes) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Container(
          decoration: box,
          // `.memory` rather than `.file`: it is the one constructor that
          // exists on mobile *and* web, so students in a browser get a real
          // document instead of a compile error.
          child: Stack(
            children: [
              Positioned.fill(
                child: SfPdfViewer.memory(
                  bytes,
                  controller: controller,
                  canShowScrollHead: false,
                  maxZoomLevel: kZoomMax,
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: _PdfZoomBar(controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _image() {
    if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      return _zoomable(
        Image.network(
          remoteUrl!,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined,
              size: 44, color: AppColors.muted),
        ),
      );
    }
    final path = doc.localPath;
    if (path == null || path.isEmpty) {
      return const Icon(Icons.broken_image_outlined,
          size: 44, color: AppColors.muted);
    }
    return _LocalFile<Uint8List>(
      path: path,
      load: localFileReadBytes,
      onMissing: const Icon(Icons.broken_image_outlined,
          size: 44, color: AppColors.muted),
      builder: (context, bytes) => _zoomable(
        Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image_outlined,
                  size: 44, color: AppColors.muted),
        ),
      ),
    );
  }

  /// Pinch or drag to zoom a photo, and double tap into the spot you tapped.
  ///
  /// The double tap has to be owned by a detector that also knows about the
  /// tap that clears the interface off the screen, or the two fight: the tap
  /// fires on each half of a double tap and the chrome flickers while the
  /// picture zooms. See ChromeTapAnywhere in chrome_toggle.dart, which claims
  /// the second tap.
  Widget _zoomable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void handleDoubleTap(Offset position) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          _imageZoom.toggleZoomAt(
            box.globalToLocal(position),
            Size(constraints.maxWidth, constraints.maxHeight),
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _imageZoom.transform,
                minScale: kZoomMin,
                maxScale: kZoomMax,
                boundaryMargin: const EdgeInsets.all(80),
                trackpadScrollCausesScale: true,
                child: GestureDetector(
                  onDoubleTapDown: (d) => _pendingTap = d.globalPosition,
                  onDoubleTap: () {
                    final tap = _pendingTap;
                    _pendingTap = null;
                    if (tap != null) handleDoubleTap(tap);
                  },
                  child: child,
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: DocumentZoomBar(target: _imageZoom.target),
            ),
          ],
        );
      },
    );
  }

  Offset? _pendingTap;

  Widget _text(BoxDecoration box) {
    final path = doc.localPath;
    if (path == null || path.isEmpty) {
      return _MissingFile(box: box, name: doc.name);
    }
    return Container(
      decoration: box,
      padding: const EdgeInsets.all(16),
      child: _LocalFile<String>(
        path: path,
        load: localFileReadString,
        onMissing:
            const Center(child: Text('Could not read this text file.')),
        builder: (context, text) => SingleChildScrollView(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Reads a picked local file exactly once and rebuilds from the result.
///
/// Deliberately stateful: the previous `FutureBuilder(File(path).readAsString())`
/// built a *new* future on every frame, so the read restarted each rebuild.
/// The future is cached here and only recreated when [path] actually changes.
class _LocalFile<T> extends StatefulWidget {
  final String path;
  final Future<T?> Function(String path) load;
  final Widget Function(BuildContext context, T data) builder;
  final Widget onMissing;

  const _LocalFile({
    super.key,
    required this.path,
    required this.load,
    required this.builder,
    required this.onMissing,
  });

  @override
  State<_LocalFile<T>> createState() => _LocalFileState<T>();
}

class _LocalFileState<T> extends State<_LocalFile<T>> {
  late Future<T?> _pending;

  @override
  void initState() {
    super.initState();
    _pending = widget.load(widget.path);
  }

  @override
  void didUpdateWidget(_LocalFile<T> old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _pending = widget.load(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T?>(
      future: _pending,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LoadingState(message: 'Opening…');
        }
        final data = snap.data;
        if (snap.hasError || data == null) return widget.onMissing;
        return widget.builder(context, data as T);
      },
    );
  }
}

class _MissingFile extends StatelessWidget {
  final BoxDecoration box;
  final String name;

  const _MissingFile({required this.box, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: box,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_outlined,
                size: 40, color: AppColors.muted),
            const SizedBox(height: 8),
            Text(
              '$name is no longer on this device.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Honest panel for files this device cannot open.
///
/// Modern Office files are rendered by the app, so what lands here is either a
/// legacy binary Office file, an explicitly gated document, or something the
/// host could not convert.
/// Zoom control for a PDF, driven through Syncfusion's own zoom level.
///
/// PDF zooms through Syncfusion's pipeline and Office through ours, so the
/// bar needs the adapter rather than the canvas transform.
class _PdfZoomBar extends StatelessWidget {
  final PdfViewerController controller;

  const _PdfZoomBar(this.controller);

  @override
  Widget build(BuildContext context) =>
      DocumentZoomBar(target: PdfZoomTarget(controller));
}

class _ConversionPanel extends StatelessWidget {
  final SharedDocument doc;
  final BoxDecoration box;

  const _ConversionPanel({required this.doc, required this.box});

  @override
  Widget build(BuildContext context) {
    final legacy = SupportedFiles.isLegacyOffice(doc.extension);
    final failed = doc.status == DocStatus.conversionFailed;
    final working = doc.status == DocStatus.converting;
    final title = working
        ? 'Converting to PDF…'
        : failed
            ? 'Could not read this file'
            : legacy
                ? 'Old .${doc.extension} format'
                : doc.status == DocStatus.unsupported
                    ? 'Not a supported file'
                    : 'Waiting for the host';
    final body = working
        ? 'This ${_label(doc.kind)} file is being converted on the host.'
        : failed
            ? 'Re-save the file and share it again, or share a PDF instead.'
            : legacy
                ? 'Files saved by Office 97-2003 use a format no device can '
                    'open. Open it once and choose "Save as" the newer '
                    'format (or a PDF), then share that file.'
                : doc.status == DocStatus.unsupported
                    ? 'This format is not supported. Use PDF, PPTX, DOCX, '
                        'XLSX, JPG, PNG, or TXT.'
                    : 'This ${_label(doc.kind)} file is waiting to be '
                        'converted to PDF on the host.';
    final icon = working
        ? Icons.sync
        : failed
            ? Icons.error_outline
            : legacy
                ? Icons.warning_amber_rounded
                : Icons.picture_as_pdf_outlined;

    return Container(
      decoration: box,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 40,
              color: failed ? AppColors.error : AppColors.warning,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.muted, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(DocKind kind) {
    switch (kind) {
      case DocKind.powerpoint:
        return 'PowerPoint';
      case DocKind.word:
        return 'Word';
      case DocKind.excel:
        return 'Excel';
      default:
        return 'Office';
    }
  }
}