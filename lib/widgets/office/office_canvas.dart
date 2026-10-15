import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../document_zoom.dart';

/// Upper bound on the pixel width an embedded image is decoded at.
///
/// Plenty for a phone screen, and it is the difference between a photo-heavy
/// deck costing a few MB of bitmaps and a few hundred: without it every
/// picture is decoded at full source resolution regardless of how small it is
/// drawn, which is the main source of image-cache churn in scroll mode.
const int kDecodeCapPx = 1600;

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

  /// Shared zoom state, owned above the pages so turning a page does not
  /// throw the zoom away. Null gives this canvas its own, which is what a
  /// one-off page wants.
  final DocumentZoom? zoom;

  const OfficeCanvas({
    super.key,
    required this.widthPt,
    required this.heightPt,
    required this.child,
    this.background = Colors.white,
    this.maxScale = 6,
    this.zoom,
  });

  @override
  State<OfficeCanvas> createState() => _OfficeCanvasState();
}

class _OfficeCanvasState extends State<OfficeCanvas> {
  final TransformationController _ownTransform = TransformationController();
  final GlobalKey _surface = GlobalKey();

  /// The shared zoom when one was handed in, this canvas's own otherwise.
  TransformationController get _transform =>
      widget.zoom?.transform ?? _ownTransform;

  @override
  void dispose() {
    _ownTransform.dispose();
    super.dispose();
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

        // The tap position is needed in the page's own coordinates so a
        // double tap can zoom into the spot that was actually touched.
        void handleDoubleTap(Offset position) {
          final box = _surface.currentContext?.findRenderObject() as RenderBox?;
          if (box == null) {
            _transform.value = Matrix4.identity();
            return;
          }
          final local = box.globalToLocal(position);
          final shared = widget.zoom;
          if (shared != null) {
            shared.toggleZoomAt(local, available);
            return;
          }
          final zoomedIn = _transform.value.getMaxScaleOnAxis() > 1.05;
          _transform.value = zoomedIn
              ? Matrix4.identity()
              : Matrix4.diagonal3Values(_doubleTapScale, _doubleTapScale, 1);
        }

        return KeyedSubtree(
          key: _surface,
          child: InteractiveViewer(
            transformationController: _transform,
            minScale: 1,
            maxScale: widget.maxScale,
            // Slack around the page so a zoomed-in edge can still be dragged
            // back into view.
            boundaryMargin: const EdgeInsets.all(120),
            // Wheel and trackpad now zoom too. A teacher working from a
            // laptop had nothing but a double click before.
            trackpadScrollCausesScale: true,
            scaleFactor: 200,
            child: GestureDetector(
              onDoubleTapDown: (d) => _pendingTap = d.localPosition,
              onDoubleTap: () {
                final tap = _pendingTap;
                _pendingTap = null;
                if (tap != null) handleDoubleTap(_toGlobal(tap));
              },
              child: FittedBox(fit: BoxFit.fill, child: page),
            ),
          ),
        );
      },
    );
  }

  Offset? _pendingTap;

  /// The surface is fitted by its parent, so the canvas needs the global
  /// position to turn the tap into a viewport point.
  Offset _toGlobal(Offset local) {
    final box = _surface.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.localToGlobal(local);
  }

  double get _doubleTapScale => widget.maxScale > 2.5 ? 2.5 : widget.maxScale;
}
