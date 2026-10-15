import 'package:flutter/material.dart';

/// Small, shared motion vocabulary.
///
/// Everything here is finite: a screen that never settles is a screen that
/// keeps a phone's battery awake and makes widget tests hang, so there are no
/// loops, no pulsing and no auto-playing anything.
class Motion {
  /// The app's standard durations. One place to change the feel.
  static const quick = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 260);
  static const page = Duration(milliseconds: 320);

  /// Stagger for list-like entrances: each item waits a little longer.
  static Duration stagger(int index) =>
      Duration(milliseconds: (index.clamp(0, 8)) * 45);

  static const slideIn = Offset(0, 0.04);
}

/// Fades and lifts its child in once, after an optional delay.
///
/// Used to make a screen arrive instead of just appearing — the cheapest way
/// to make an app feel designed rather than assembled.
class FadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double rise;

  const FadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = Motion.standard,
    this.rise = 14,
  });

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );

  /// The delay is an *interval on one controller*, never a `Future.delayed`:
  /// a real timer outlives the widget, which leaks in production and fails the
  /// widget tests with "a Timer is still pending".
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _delayFraction,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  double get _delayFraction {
    final total = (widget.delay + widget.duration).inMicroseconds;
    if (total <= 0) return 0;
    return (widget.delay.inMicroseconds / total).clamp(0.0, 0.99);
  }

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.rise * (1 - _curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Tap feedback: a small, fast press-down. Tiles are the main tap target in
/// this app, and a plain InkWell reads as "web page" rather than "app".
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Motion.quick,
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: widget.onTap == null ? 0.55 : 1,
          duration: Motion.quick,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Cross-fades between pages when [page] changes.
///
/// Office documents are drawn by the app, so turning a page has to be animated
/// by hand — without this it looks like a frame dropped. Deliberately *not*
/// used for PDFs: rebuilding the viewer widget to animate a page turn would
/// throw away the already-rendered document.
class PageSwitcher extends StatelessWidget {
  final Object identity;
  final Widget child;

  const PageSwitcher({
    super.key,
    required this.identity,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.page,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.02, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(identity), child: child),
    );
  }
}