import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/doc_types.dart';
import '../models/shared_document.dart';
import '../theme/app_colors.dart';

/// Renders the real shared document.
///
/// - PDF  → Syncfusion viewer on the local file (teacher) or the host URL
///          (student), with page control driven by the teacher.
/// - Image / text → rendered directly.
/// - Office (ppt/doc/xls) → honest "needs conversion" panel. Flutter cannot
///   render those natively; they are converted on a compatible laptop host.
class DocumentViewer extends StatelessWidget {
  final SharedDocument doc;
  final PdfViewerController controller;

  /// Remote URL for students (served by the teacher host). When null the
  /// viewer falls back to the local file picked on this device.
  final String? remoteUrl;

  /// When true, show the conversion panel instead of a preview.
  final bool showConversionPanel;

  const DocumentViewer({
    super.key,
    required this.doc,
    required this.controller,
    this.remoteUrl,
    this.showConversionPanel = false,
  });

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

  Widget _pdf(BoxDecoration box) {
    // Students fetch from the teacher host; the teacher renders the file it
    // picked directly. Never fall back to a bundled sample asset.
    if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.large),
        child: Container(
          decoration: box,
          child: SfPdfViewer.network(
            remoteUrl!,
            controller: controller,
            canShowScrollHead: false,
          ),
        ),
      );
    }
    final path = doc.localPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return _MissingFile(box: box, name: doc.name);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.large),
      child: Container(
        decoration: box,
        child: SfPdfViewer.file(
          File(path),
          controller: controller,
          canShowScrollHead: false,
        ),
      ),
    );
  }

  Widget _image() {
    if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      return Image.network(
        remoteUrl!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined,
            size: 44, color: AppColors.muted),
      );
    }
    final path = doc.localPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return const Icon(Icons.broken_image_outlined,
          size: 44, color: AppColors.muted);
    }
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined,
          size: 44, color: AppColors.muted),
    );
  }

  Widget _text(BoxDecoration box) {
    final path = doc.localPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return _MissingFile(box: box, name: doc.name);
    }
    return Container(
      decoration: box,
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<String>(
        future: File(path).readAsString(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingState(message: 'Opening…');
          }
          if (snap.hasError) {
            return const Center(
              child: Text('Could not read this text file.'),
            );
          }
          return SingleChildScrollView(
            child: Text(
              snap.data ?? '',
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          );
        },
      ),
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

/// Honest panel for Office formats that Flutter cannot render natively.
class _ConversionPanel extends StatelessWidget {
  final SharedDocument doc;
  final BoxDecoration box;

  const _ConversionPanel({required this.doc, required this.box});

  @override
  Widget build(BuildContext context) {
    final failed = doc.status == DocStatus.conversionFailed;
    final working = doc.status == DocStatus.converting;
    return Container(
      decoration: box,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              working
                  ? Icons.sync
                  : failed
                      ? Icons.error_outline
                      : Icons.picture_as_pdf_outlined,
              size: 40,
              color: failed ? AppColors.error : AppColors.warning,
            ),
            const SizedBox(height: 10),
            Text(
              working
                  ? 'Converting to PDF…'
                  : failed
                      ? 'Conversion failed'
                      : 'Convert to PDF first',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              working
                  ? 'This ${_label(doc.kind)} file is being converted on the host.'
                  : failed
                      ? 'Try a laptop with LibreOffice, or share a PDF instead.'
                      : 'This ${_label(doc.kind)} file cannot be shown '
                          'directly. Convert it to PDF on a laptop host '
                          '(LibreOffice), then share the PDF.',
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

/// Base64 helper for hosts that inline small documents over the socket.
String? tryDecodeText(String value) {
  try {
    return utf8.decode(base64Decode(value));
  } catch (_) {
    return null;
  }
}