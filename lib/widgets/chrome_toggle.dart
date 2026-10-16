import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Puts the interface around a document away so the page is all that is left.
///
/// A presenter taps the slide to clear the app bar, the page controls and the
/// session bar out of the way, then taps it again to get them back. The value
/// lives in a [ChangeNotifier] rather than in one screen's `setState` because
/// the chrome and the page belong to different widgets — the app bar to the
/// shell, the document to the viewer — and both have to move together.
class ChromeController extends ChangeNotifier {
  bool _hidden = false;

  bool get hidden => _hidden;

  void toggle() {
    _hidden = !_hidden;
    notifyListeners();
  }

  /// Brings the chrome back, and does nothing if it is already showing. Safe to
  /// call unconditionally when leaving a full-screen view.
  void show() {
    if (!_hidden) return;
    _hidden = false;
    notifyListeners();
  }
}

/// Publishes a [ChromeController] to the subtree and rebuilds every widget
/// that reads it when the value changes.
class ChromeToggleScope extends InheritedNotifier<ChromeController> {
  const ChromeToggleScope({
    super.key,
    required ChromeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Null outside a scope, so a screen can be reused with or without one.
  static ChromeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChromeToggleScope>()?.notifier;
}

/// Flips the chrome from a tap on the page itself.
///
/// Translucent, and it only ever listens for a tap: a scroll, a page turn, a
/// pinch and every button are claimed by the document underneath, so this only
/// fires on bare page surface — which is exactly the gesture that should clear
/// the chrome and the one that should bring it back.
///
/// [onDoubleTap] is the reason the document underneath can own a double tap.
/// Without a double-tap handler here, the first tap wins the gesture arena,
/// `onTap` fires, and the second tap fires it again — so double tapping the
/// slide toggled the interface off and straight back on while the page zoomed
/// underneath it. Declaring a no-op double tap makes this recogniser compete
/// for the second tap; the inner one wins, the page zooms, and `onTap` is
/// cancelled rather than fired twice.
class ChromeTapAnywhere extends StatelessWidget {
  final Widget child;

  const ChromeTapAnywhere({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeToggleScope.maybeOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: chrome?.toggle,
      onDoubleTap: () {},
      child: child,
    );
  }
}

/// The app bar's half of the toggle, so the chrome can also be dismissed
/// without reaching for the page.
class ChromeAppBarAction extends StatelessWidget {
  const ChromeAppBarAction({super.key});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeToggleScope.maybeOf(context);
    if (chrome == null) return const SizedBox.shrink();
    final hidden = chrome.hidden;
    return IconButton(
      tooltip: hidden ? 'Show controls' : 'Hide controls',
      iconSize: 20,
      icon: Icon(hidden
          ? Icons.visibility_outlined
          : Icons.visibility_off_outlined),
      onPressed: chrome.toggle,
    );
  }
}

/// The way back from hidden chrome, for anyone who does not think to tap the
/// page. A quiet pill over the bottom edge, shown only while the chrome is
/// away.
class ChromeToggleHint extends StatelessWidget {
  final String label;

  const ChromeToggleHint({super.key, this.label = 'Show controls'});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeToggleScope.maybeOf(context);
    if (chrome == null || !chrome.hidden) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Semantics(
            button: true,
            label: label,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: chrome.show,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.visibility_outlined,
                          size: 18, color: Colors.white),
                      const SizedBox(width: AppSpacing.s8),
                      Text(label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
