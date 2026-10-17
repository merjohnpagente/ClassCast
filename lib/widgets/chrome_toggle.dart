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

  /// When the last accepted toggle landed.
  int _lastToggleMs = 0;

  /// A double tap on the page fires this twice in quick succession, because
  /// the document underneath owns the double tap and the page's own tap fires
  /// on each half of the gesture. Toggling twice nets back to where it
  /// started, which means the interface flickered away and back for every
  /// zoom. Dropping the second one leaves the zoom visible and the interface
  /// still showing, which is what the teacher meant.
  ///
  /// This lives here rather than in a competing `onDoubleTap` gesture
  /// recogniser, because a recogniser on the ancestor beats the "Show
  /// controls" pill's own tap and takes the way back with it.
  static const _debounce = Duration(milliseconds: 250);

  bool get hidden => _hidden;

  void toggle() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastToggleMs < _debounce.inMilliseconds) return;
    _lastToggleMs = now;
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
/// There is deliberately no `onDoubleTap` here, even though the document
/// underneath owns one. Adding it looked like the tidy fix for a double tap
/// firing this twice, and it broke the thing that matters: a competing double
/// tap recogniser on the ancestor wins the gesture arena over the "Show
/// controls" pill's own tap, so the only way back out of a hidden interface
/// stopped working. [ChromeController.toggle] absorbs the double instead.
class ChromeTapAnywhere extends StatelessWidget {
  final Widget child;

  const ChromeTapAnywhere({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeToggleScope.maybeOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: chrome?.toggle,
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
/// page. A small dark circle in the bottom-left corner, shown only while the
/// chrome is away.
///
/// It used to be a labelled pill along the bottom centre, where on a phone it
/// sat right on top of the zoom bar anchored to the bottom-right — the pill
/// covered the −/+/Fit buttons and, being the top layer of the stack, stole
/// their taps. A corner circle cannot collide with anything: the zoom bar owns
/// the bottom-right, this owns the bottom-left.
class ChromeToggleHint extends StatelessWidget {
  final String label;

  const ChromeToggleHint({super.key, this.label = 'Show controls'});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeToggleScope.maybeOf(context);
    if (chrome == null || !chrome.hidden) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomLeft,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Semantics(
            button: true,
            label: label,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: chrome.show,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.visibility_outlined,
                      size: 20, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
