import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/responsive.dart';

/// Responsive shell: bottom nav on phones, sidebar on desktop.
/// [destinations] drives both. [panel] is an optional right-side panel
/// (session info) on wide screens.
class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<AppDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onNavigate;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? panel;
  final bool showBack;

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
  });

  @override
  Widget build(BuildContext context) {
    if (context.isDesktop) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: showBack,
          title: Text(title),
          actions: actions,
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            Expanded(
              child: ContentWidth(
                child: Padding(
                  padding:
                      EdgeInsets.all(context.pagePadding),
                  child: body,
                ),
              ),
            ),
            if (panel != null) ...[
              const VerticalDivider(width: 1),
              SizedBox(width: 300, child: panel!),
            ],
          ],
        ),
        floatingActionButton: floatingActionButton,
      );
    }
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: showBack,
        title: Text(title),
        actions: actions,
      ),
      body: Padding(
        padding: EdgeInsets.all(context.pagePadding),
        child: body,
      ),
      bottomNavigationBar: NavigationBar(
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
      ),
      floatingActionButton: floatingActionButton,
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

/// Compact nav header card used above page content on phones.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    )),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        )),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
