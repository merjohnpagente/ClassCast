import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Applies an opacity to an OOXML `0xAARRGGBB` colour.
///
/// Written by hand rather than with `Color.withOpacity` / `withValues` so the
/// same code compiles on every Flutter version the repo supports.
Color argbWithOpacity(int argb, double opacity) {
  final alpha = ((opacity.clamp(0.0, 1.0)) * 255).round();
  return Color.fromARGB(
    alpha,
    (argb >> 16) & 0xFF,
    (argb >> 8) & 0xFF,
    argb & 0xFF,
  );
}

/// Paints a document page of a fixed logical size and scales it to fit.
///
/// Every Office renderer draws into this canvas instead of the raw screen, so a
/// slide looks identical on a phone, a laptop and a projector — and, crucially,
/// "page 3" means the same content everywhere.
///
/// The page is wrapped in an [InteractiveViewer]: a teacher needs to pinch into
/// a small label on a slide or drag across a page that is taller than the
/// screen. Page 1 still starts fitted, so the default view is unchanged.
class OfficeCanvas extends StatefulWidget {
  final double widthPt;
  final double heightPt;
  final Color background;
  final Widget child;

  /// How far a teacher can zoom in. 6x is enough to read fine print on a
  /// projected slide without turning the page into an abstract.
  final double maxScale;

  const OfficeCanvas({
    super.key,
    required this.widthPt,
    required this.heightPt,
    required this.child,
    this.background = Colors.white,
    this.maxScale = 6,
  });

  @override
  State<OfficeCanvas> createState() => _OfficeCanvasState();
}

class _OfficeCanvasState extends State<OfficeCanvas> {
  final TransformationController _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Back to "whole page" — the escape hatch for a zoomed-in teacher.
  void _reset() {
    _transform.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = math.min(
          available.width / widget.widthPt,
          available.height / widget.heightPt,
        );
        final safeScale = scale.isFinite && scale > 0 ? scale : 1.0;
        final width = widget.widthPt * safeScale;
        final height = widget.heightPt * safeScale;

        final page = SizedBox(
          width: widget.widthPt,
          height: widget.heightPt,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.background,
              border: Border.all(color: const Color(0x14000000)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ClipRect(child: widget.child),
          ),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: SizedBox(
                width: width,
                height: height,
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: widget.maxScale,
                  // Slack around the page so a zoomed-in edge can still be
                  // dragged back into view.
                  boundaryMargin: const EdgeInsets.all(120),
                  child: FittedBox(fit: BoxFit.fill, child: page),
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: _resetButton(),
            ),
          ],
        );
      },
    );
  }

  Widget _resetButton() {
    return ValueListenableBuilder<Matrix4>(
      valueListenable: _transform,
      builder: (context, matrix, _) {
        final zoomed = matrix.getMaxScaleOnAxis() > 1.01;
        if (!zoomed) return const SizedBox.shrink();
        return Material(
          color: Colors.black.withAlpha(140),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _reset,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_out_map, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Fit page',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
