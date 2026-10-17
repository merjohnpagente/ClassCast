import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Puts the interface around a document away so the page is all that is left.
///
/// The app bar carries the toggle — the eye button — and the page itself no
/// longer reacts to taps: a tap on a slide is how the document underneath is
/// paged or zoomed, so it must never take the interface away with it. The
/// value lives in a [ChangeNotifier] rather than in one screen's `setState`
/// because the chrome and the page belong to different widgets — the app bar
/// to the shell, the document to the viewer — and both have to move together.
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

/// The app bar's half of the toggle, so the chrome can be dismissed
/// without leaving the screen.
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

/// The way back from hidden chrome, so the eye button is not the only way to
/// get the interface back.
///
/// Top-left, and it used to be bottom-left: a bottom corner was chosen because
/// the zoom bar owns the bottom-*right*. Then a video arrived, and its controls
/// span the whole bottom edge — so the button landed on top of play/pause and
/// a tap meant two different things. The top of the page is the one edge no
/// document control claims: the app bar is gone by definition, and everything
/// else — zoom bar, page row, video transport — lives at the bottom.
class ChromeToggleHint extends StatelessWidget {
  final String label;

  const ChromeToggleHint({super.key, this.label = 'Show controls'});

  @override
  Widget build(BuildContext context) {
    final chrome = ChromeToggleScope.maybeOf(context);
    if (chrome == null || !chrome.hidden) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topLeft,
      child: SafeArea(
        bottom: false,
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
