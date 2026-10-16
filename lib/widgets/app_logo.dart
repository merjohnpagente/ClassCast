import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// ClassCast Offline logo: a presentation screen + wireless cast arcs.
/// Minimal, blue, scalable — launcher, splash, header, favicon.
///
/// [color] exists so the mark can sit on the blue splash as well as on white.
/// The splash used to draw a blue mark on a blue field, which is a logo you
/// cannot see.
class AppLogo extends StatelessWidget {
  final double size;
  final bool filled;
  final Color? color;

  const AppLogo({super.key, this.size = 64, this.filled = false, this.color});

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? AppColors.primary,
          borderRadius: BorderRadius.circular(size * 0.24),
        ),
        child: CustomPaint(painter: _LogoPainter(Colors.white)),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LogoPainter(color ?? AppColors.primary),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final Color color;
  _LogoPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    // Screen outline (open bottom edge like a cast icon).
    final screen = Path()
      ..moveTo(w * 0.14, h * 0.82)
      ..lineTo(w * 0.14, h * 0.18)
      ..lineTo(w * 0.86, h * 0.18)
      ..lineTo(w * 0.86, h * 0.66);
    canvas.drawPath(screen, paint);

    // Cast arcs (bottom-left origin).
    final dot = Paint()..color = color;
    canvas.drawCircle(Offset(w * 0.24, h * 0.72), w * 0.035, dot);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w * 0.24, h * 0.72), radius: w * 0.13),
      -1.5708,
      1.5708,
      false,
      paint,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(w * 0.24, h * 0.72), radius: w * 0.23),
      -1.5708,
      1.5708,
      false,
      paint,
    );
    // Stand.
    canvas.drawLine(
      Offset(w * 0.38, h * 0.86),
      Offset(w * 0.62, h * 0.86),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
