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
///
/// The cap exists so a list of file cards or a block of settings text does not
/// stretch to a metre across a 27-inch monitor, and so it does not shrink to
/// nothing on a phone. A presentation is neither: it is a page that should use
/// whatever room it is given. [wide] raises the cap for the screens that show
/// one — the board — and only those, so text-heavy screens keep their measure.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  /// Lets a document use the screen instead of a reading column.
  final bool wide;

  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 1100,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? _wideMax : maxWidth),
        child: child,
      ),
    );
  }

  /// A page is readable from the back of a room at this width; past it, the
  /// extra space would only shrink the type relative to the screen.
  static const double _wideMax = 1600;
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
