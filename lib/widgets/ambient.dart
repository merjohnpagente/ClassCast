import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'motion.dart';

/// Looping scenery for the screens where the app is waiting for a person:
/// role selection, the join form and the waiting room.
///
/// These are the only loops in the app. They sit on the screens a first-time
/// user stares at, where a still page reads as a frozen app — and never on the
/// document screens, where a loop would spend a phone's battery behind a
/// worksheet for nothing.
///
/// Everything here goes quiet when [Motion.ambient] is off (widget tests) or
/// when the phone asks for reduced motion, and draws its first frame instead.
class AmbientBackdrop extends StatelessWidget {
  /// The wireframe globe costs the most to paint, so the smaller screens skip
  /// it and keep the drifting colour only.
  final bool globe;

  const AmbientBackdrop({super.key, this.globe = true});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: _Loop(
          period: const Duration(seconds: 24),
          builder: (context, t, child) => CustomPaint(
            painter: _BackdropPainter(t, AppColors.active, globe: globe),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// A soft radar pulse behind whatever the screen is waiting on.
class PulseRings extends StatelessWidget {
  final double size;
  final Widget? child;

  const PulseRings({super.key, this.size = 120, this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: _Loop(
        period: const Duration(milliseconds: 2600),
        child: child,
        builder: (context, t, child) => CustomPaint(
          painter: _RingsPainter(t, AppColors.active),
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

/// A gentle 3D tilt that never stops, for the pieces that should feel like
/// objects rather than pixels. [phase] staggers neighbours so a column of
/// cards does not wobble in lockstep.
class Wobble3D extends StatelessWidget {
  final Widget child;
  final double tilt;
  final double phase;
  final Duration period;

  const Wobble3D({
    super.key,
    required this.child,
    this.tilt = 0.045,
    this.phase = 0,
    this.period = const Duration(seconds: 9),
  });

  @override
  Widget build(BuildContext context) {
    return _Loop(
      period: period,
      child: child,
      builder: (context, t, child) {
        final a = math.sin(_tau(t + phase));
        final b = math.cos(_tau(t * 0.8 + phase));
        // The `setEntry(3, 2, ...)` term is what makes this read as depth
        // rather than a skew: without it rotateX/rotateY are flat.
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateX(a * tilt)
            ..rotateY(b * tilt * 1.3),
          child: child,
        );
      },
    );
  }
}

/// One repeating clock, shared by everything above.
///
/// The loop runs only while the widget is mounted *and* allowed to move; the
/// widget tests turn it off so `pumpAndSettle` can finish, and phones with
/// "reduce motion" on get the still first frame.
class _Loop extends StatefulWidget {
  final Duration period;
  final Widget? child;
  final Widget Function(BuildContext context, double t, Widget? child) builder;

  const _Loop({required this.period, required this.builder, this.child});

  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !Motion.ambient || MediaQuery.of(context).disableAnimations;
    if (still) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) =>
          widget.builder(context, _controller.value, child),
    );
  }
}

double _tau(double turns) => turns * 2 * math.pi;

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.t, this.palette, {required this.globe});

  final double t;
  final AppPalette palette;
  final bool globe;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = palette.isDark;
    _blob(
      canvas,
      size,
      center: sizeRect(size, 0.14 + 0.05 * math.sin(_tau(t) + 0.4),
          0.12 + 0.04 * math.cos(_tau(t * 0.8))),
      radius: size.shortestSide * 0.46,
      color: palette.primary.withValues(alpha: dark ? 0.22 : 0.10),
    );
    _blob(
      canvas,
      size,
      center: sizeRect(size, 0.88 + 0.04 * math.sin(_tau(t * 0.7) + 2.1),
          0.34 + 0.05 * math.cos(_tau(t * 0.9) + 1.2)),
      radius: size.shortestSide * 0.40,
      color: palette.secondary.withValues(alpha: dark ? 0.18 : 0.09),
    );
    _blob(
      canvas,
      size,
      center: sizeRect(size, 0.42 + 0.06 * math.sin(_tau(t * 0.6) + 4.0),
          0.98 + 0.03 * math.cos(_tau(t * 0.75) + 3.3)),
      radius: size.shortestSide * 0.44,
      color: palette.primary.withValues(alpha: dark ? 0.14 : 0.07),
    );
    if (globe) _globe(canvas, size);
  }

  static Offset sizeRect(Size size, double fx, double fy) =>
      Offset(size.width * fx, size.height * fy);

  void _blob(Canvas canvas, Size size,
      {required Offset center, required double radius, required Color color}) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(rect),
    );
  }

  /// A slow dot-globe, turning on its axis.
  ///
  /// Fibonacci-sphere points so the dots stay evenly spread without poles
  /// clumping, then plain hand-rolled rotation and a perspective divide — a
  /// real matrix package would be a dependency for thirty lines of arithmetic.
  void _globe(Canvas canvas, Size size) {
    final dark = palette.isDark;
    final center = Offset(size.width * 0.84, size.height * 0.15);
    final radius = size.shortestSide * 0.32;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [
          palette.primary.withValues(alpha: dark ? 0.10 : 0.05),
          palette.primary.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    final angle = _tau(t);
    const tilt = 0.42;
    final front = Paint()
      ..color = palette.primary.withValues(alpha: dark ? 0.42 : 0.26)
      ..style = PaintingStyle.fill;
    final back = Paint()
      ..color = palette.primary.withValues(alpha: dark ? 0.15 : 0.09)
      ..style = PaintingStyle.fill;

    const count = 150;
    for (var i = 0; i < count; i++) {
      final y = 1 - (i / (count - 1)) * 2;
      final ring = math.sqrt(math.max(0, 1 - y * y));
      final phi = i * 2.399963229728653; // golden angle
      final x = math.cos(phi) * ring;
      final z = math.sin(phi) * ring;
      // Spin around the vertical axis...
      final x1 = x * math.cos(angle) + z * math.sin(angle);
      final z1 = -x * math.sin(angle) + z * math.cos(angle);
      // ...then lean the whole thing towards the viewer a little.
      final y2 = y * math.cos(tilt) - z1 * math.sin(tilt);
      final z2 = y * math.sin(tilt) + z1 * math.cos(tilt);
      final scale = 1 / (1 + z2 * 0.55);
      final point =
          center + Offset(x1 * radius * scale, y2 * radius * scale);
      // The far side of the globe: smaller and fainter, which is the depth
      // cue that makes a flat circle read as a sphere.
      canvas.drawCircle(point, z2 > 0 ? 1.1 * scale : 1.9 * scale,
          z2 > 0 ? back : front);
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.t != t || old.palette != palette || old.globe != globe;
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t, this.palette);

  final double t;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0;
      paint.color =
          palette.primary.withValues(alpha: (1 - phase) * 0.35);
      canvas.drawCircle(center, maxRadius * (0.30 + 0.70 * phase), paint);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) =>
      old.t != t || old.palette != palette;
}
