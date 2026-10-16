import 'package:flutter/material.dart';

import '../utils/responsive.dart';
import 'motion.dart';

/// Responsive shell: bottom nav on phones, sidebar on desktop.
/// [destinations] drives both. [panel] is an optional right-side panel
/// (session info) on wide screens.
class AppScaffold extends StatefulWidget {
  final String title;
  final Widget body;
  final List<AppDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onNavigate;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? panel;
  final bool showBack;

  /// Whether the app bar and the navigation are drawn at all.
  ///
  /// The full-screen document view turns this off so the page is the only
  /// thing on the phone; it puts the outer padding back too, because a slide
  /// inset inside two sets of page margins is not really filling the screen.
  final bool showChrome;

  /// Explicit back affordance.
  ///
  /// Needed by the role shells: they are the app's `home` route, so
  /// `Navigator.canPop()` is false and `automaticallyImplyLeading` silently
  /// draws nothing, leaving users with no way back to role selection.
  final VoidCallback? onBack;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.destinations,
    required this.currentIndex,
    required this.onNavigate,
    this.actions,
    this.floatingActionButton,
    this.panel,
    this.showBack = false,
    this.showChrome = true,
    this.onBack,
  });

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  Widget? _leading() {
    if (widget.onBack == null) return null;
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: 'Back',
      onPressed: widget.onBack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final body = widget.body;
    final destinations = widget.destinations;
    final currentIndex = widget.currentIndex;
    final onNavigate = widget.onNavigate;
    final actions = widget.actions;
    final floatingActionButton = widget.floatingActionButton;
    final panel = widget.panel;
    final showBack = widget.showBack;
    final showChrome = widget.showChrome;
    final appBar = showChrome
        ? AppBar(
            automaticallyImplyLeading: showBack,
            leading: _leading(),
            title: Text(title),
            actions: actions,
          )
        : null;

    if (context.isDesktop) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showChrome) ...[
              NavigationRail(
                selectedIndex: currentIndex,
                onDestinationSelected: onNavigate,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon ?? d.icon),
                      label: Text(d.label),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: showChrome
                  ? ContentWidth(
                      child: Padding(
                        padding: EdgeInsets.all(context.pagePadding),
                        child: _withTabFade(body),
                      ),
                    )
                  : _withTabFade(body),
            ),
            if (panel != null) ...[
              const VerticalDivider(width: 1),
              SizedBox(width: 300, child: panel),
            ],
          ],
        ),
        floatingActionButton: floatingActionButton,
      );
    }
    return Scaffold(
      appBar: appBar,
      body: showChrome
          ? Padding(
              padding: EdgeInsets.all(context.pagePadding),
              child: ContentWidth(
                maxWidth: 720,
                child: _withTabFade(body),
              ),
            )
          : _withTabFade(body),
      bottomNavigationBar: showChrome
          ? NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: onNavigate,
              destinations: [
                for (final d in destinations)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon ?? d.icon),
                    label: d.label,
                  ),
              ],
            )
          : null,
      floatingActionButton: floatingActionButton,
    );
  }

  /// A short dip on tab change. The tab screens keep their state underneath,
  /// so this reads as a cross-fade rather than a rebuild.
  Widget _withTabFade(Widget child) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.currentIndex),
      tween: Tween<double>(begin: 0.72, end: 1),
      duration: Motion.standard,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) =>
          Opacity(opacity: value, child: child),
      child: child,
    );
  }
}

class AppDestination {
  final String label;
  final IconData icon;
  final IconData? selectedIcon;

  const AppDestination({
    required this.label,
    required this.icon,
    this.selectedIcon,
  });
}
