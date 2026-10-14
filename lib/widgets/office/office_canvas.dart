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
class OfficeCanvas extends StatelessWidget {
  final double widthPt;
  final double heightPt;
  final Color background;
  final Widget child;

  const OfficeCanvas({
    super.key,
    required this.widthPt,
    required this.heightPt,
    required this.child,
    this.background = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = math.min(
          available.width / widthPt,
          available.height / heightPt,
        );
        final safeScale = scale.isFinite && scale > 0 ? scale : 1.0;
        final width = widthPt * safeScale;
        final height = heightPt * safeScale;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: widthPt,
                height: heightPt,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: background,
                    border: Border.all(color: const Color(0x14000000)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRect(child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
