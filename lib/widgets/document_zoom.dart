import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

/// How far a document can be zoomed in, in either direction.
const double kZoomMin = 1;
const double kZoomMax = 6;

/// The stops a +/− button walks through.
///
/// Fixed steps beat a slider here: the teacher is standing in front of a class
/// with one hand, and a button that always moves the same amount is something
/// you learn without looking at it.
const List<double> kZoomSteps = [1, 1.5, 2, 3, 4, 6];

/// Whatever is on screen, as far as zooming is concerned.
///
/// PDF is rendered by Syncfusion and Office by our own canvas, so they zoom
/// through entirely different machinery. The bar talks to this instead, which
/// is why one widget serves both.
abstract class ZoomTarget {
  /// Rebuilds whenever [scale] changes.
  Listenable get listenable;

  /// Current scale, where 1 means "fits the screen".
  double get scale;

  /// Request a scale. The caller clamps.
  set scale(double value);

  /// Back to the whole page.
  void fit();
}

/// Our own canvas: an [InteractiveViewer] and its transform.
class CanvasZoomTarget implements ZoomTarget {
  final TransformationController transform;

  CanvasZoomTarget(this.transform);

  @override
  Listenable get listenable => transform;

  @override
  double get scale => transform.value.getMaxScaleOnAxis();

  @override
  set scale(double value) {
    final next = value.clamp(kZoomMin, kZoomMax).toDouble();
    transform.value = Matrix4.diagonal3Values(next, next, 1);
  }

  @override
  void fit() => transform.value = Matrix4.identity();
}

/// Syncfusion's PDF viewer. Its `zoomLevel` is read/write, which is the only
/// handle it offers from the outside.
class PdfZoomTarget implements ZoomTarget {
  final PdfViewerController controller;

  PdfZoomTarget(this.controller);

  @override
  Listenable get listenable => controller;

  @override
  double get scale => controller.zoomLevel;

  @override
  set scale(double value) =>
      controller.zoomLevel = value.clamp(kZoomMin, kZoomMax).toDouble();

  @override
  void fit() => controller.zoomLevel = kZoomMin;
}

/// Zoom state that outlives a single page.
///
/// It is owned above the page views on purpose: each page used to own its own
/// controller, so zooming into a diagram and then turning the page threw the
/// zoom away. A teacher reading a chart does that constantly.
class DocumentZoom extends ChangeNotifier {
  DocumentZoom(this._ticker);

  /// Supplied by the owning State, which is where the ticker has to come from.
  final TickerProvider _ticker;

  final TransformationController transform = TransformationController();

  ZoomTarget get target => CanvasZoomTarget(transform);

  double get scale => transform.value.getMaxScaleOnAxis();

  bool get isZoomed => scale > 1.01;

  /// The scale a double tap jumps to: enough to read fine print, not so much
  /// that the page becomes an abstract.
  double get closeUpScale => 2.5;

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  /// Snaps to the nearest step in [direction], with a short animation so the
  /// eye can follow the page instead of it jumping.
  void step(int direction) =>
      _animateTo(_nextStep(scale, direction), focal: null);

  void fit() {
    _animation?.dispose();
    _animation = null;
    transform.value = Matrix4.identity();
    notifyListeners();
  }

  /// Double tap: zoom into the spot that was tapped.
  ///
  /// This is the difference between usable and not. Zooming to the centre of
  /// the page means tapping a small label sends it to the middle of the slide,
  /// which is worse than having no zoom at all.
  void toggleZoomAt(Offset tapped, Size viewport) {
    if (isZoomed) {
      fit();
      return;
    }
    _animateTo(closeUpScale, focal: tapped, viewport: viewport);
  }

  AnimationController? _animation;

  void _animateTo(double next, {Offset? focal, Size? viewport}) {
    final target = next.clamp(kZoomMin, kZoomMax).toDouble();
    final from = scale;
    if ((target - from).abs() < 0.001) return;

    _animation?.dispose();
    final anim = AnimationController(
      vsync: _ticker,
      duration: const Duration(milliseconds: 180),
    );
    _animation = anim;

    // Scaling about a point keeps that point under the finger. Scaling about
    // the centre is what made the old double tap feel like a glitch.
    final view = viewport ?? Size.zero;
    var dx = view.width / 2;
    var dy = view.height / 2;
    if (focal != null) {
      dx = focal.dx;
      dy = focal.dy;
    }

    anim.addListener(() {
      final t = from + (target - from) * anim.value;
      transform.value = Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(t, t, 1, 1)
        ..translateByDouble(-dx, -dy, 0, 1);
      notifyListeners();
    });
    anim.forward().whenComplete(() {
      if (_animation == anim) _animation = null;
      anim.dispose();
    });
  }

  /// The next fixed step in [direction] from [current].
  static double _nextStep(double current, int direction) {
    final steps = kZoomSteps;
    if (direction > 0) {
      return steps.firstWhere((s) => s > current + 0.01, orElse: () => kZoomMax);
    }
    final below = steps.where((s) => s < current - 0.01).toList();
    return below.isEmpty ? kZoomMin : below.last;
  }
}

/// The floating zoom control: −, the current level, +, Fit.
///
/// The same widget on the teacher's screen and a student's, because they should
/// feel like one app rather than two.
class DocumentZoomBar extends StatelessWidget {
  final ZoomTarget target;
  final VoidCallback? onFit;

  const DocumentZoomBar({
    super.key,
    required this.target,
    this.onFit,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: target.listenable,
      builder: (context, _) {
        final scale = target.scale.clamp(kZoomMin, kZoomMax);
        final zoomed = scale > 1.01;
        return Material(
          color: Colors.black.withAlpha(150),
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _button(
                  icon: Icons.remove,
                  tooltip: 'Zoom out',
                  onPressed:
                      zoomed ? () => target.scale = _nextStep(scale, -1) : null,
                ),
                // The readout doubles as the "exactly 100%" reset, so the
                // level is never something the user has to guess at.
                Tooltip(
                  message: 'Tap for exactly 100% · hold to fit the page',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => target.scale = 1,
                    onLongPress: () {
                      target.fit();
                      onFit?.call();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      child: Text(
                        '${(scale * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                _button(
                  icon: Icons.add,
                  tooltip: 'Zoom in',
                  onPressed: scale < kZoomMax - 0.01
                      ? () => target.scale = _nextStep(scale, 1)
                      : null,
                ),
                if (zoomed)
                  _button(
                    icon: Icons.zoom_out_map,
                    tooltip: 'Fit page',
                    onPressed: () {
                      target.fit();
                      onFit?.call();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static double _nextStep(double current, int direction) =>
      DocumentZoom._nextStep(current, direction);

  Widget _button({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      color: Colors.white,
      disabledColor: Colors.white24,
      icon: Icon(icon),
    );
  }
}

/// The bar positioned over whatever is being viewed.
class DocumentZoomOverlay extends StatelessWidget {
  final ZoomTarget target;
  final Widget child;

  const DocumentZoomOverlay({
    super.key,
    required this.target,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          right: 10,
          bottom: 10,
          child: DocumentZoomBar(target: target),
        ),
      ],
    );
  }
}
