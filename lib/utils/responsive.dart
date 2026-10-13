import 'package:flutter/material.dart';

/// Breakpoints + helpers for phones, tablets, laptops, desktop, web.
class Breakpoints {
  static const double phone = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isPhone => screenWidth < Breakpoints.phone;
  bool get isTablet =>
      screenWidth >= Breakpoints.phone && screenWidth < Breakpoints.desktop;
  bool get isDesktop => screenWidth >= Breakpoints.desktop;
  bool get isWide => screenWidth >= Breakpoints.phone;

  double get pagePadding => isDesktop ? 32 : (isWide ? 24 : 16);
}

/// Centers content and caps width on tablet / desktop / web.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ContentWidth({super.key, required this.child, this.maxWidth = 1100});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Grid delegate: compact list-like cards on phones, multi-column on desktop.
SliverGridDelegateWithMaxCrossAxisExtent docGridDelegate(
    {double mainExtent = 148}) {
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 360,
    mainAxisExtent: mainExtent,
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
  );
}

/// Keeps huge system font scales from breaking small-screen layouts.
Widget responsiveTextScale(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(
      textScaler:
          mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.2),
    ),
    child: child ?? const SizedBox.shrink(),
  );
}
