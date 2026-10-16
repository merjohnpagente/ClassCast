import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/lazy_tab_stack.dart';
import 'teacher_dashboard.dart';
import '../common/files_screen.dart';
import '../common/settings_screen.dart';

/// Teacher navigation shell. Mobile: bottom nav. Desktop: sidebar.
/// Tabs: Home, Files, Settings.
///
/// There is deliberately no separate Sessions tab. The design puts the session
/// list on Home, where the create button is, and a second tab holding the same
/// list made "where do I manage my classes?" a real question.
class TeacherShell extends StatefulWidget {
  const TeacherShell({super.key});

  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  int _index = 0;

  static const _destinations = [
    AppDestination(
        label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home),
    AppDestination(
        label: 'Files', icon: Icons.folder_outlined, selectedIcon: Icons.folder),
    AppDestination(
        label: 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings),
  ];

  /// One heading per tab, matching the design: the role on Home, the section
  /// everywhere else.
  static const _titles = ['Teacher', 'Files', 'Settings'];

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _titles[_index],
      destinations: _destinations,
      currentIndex: _index,
      onNavigate: (i) => setState(() => _index = i),
      // This shell is the app's home route, so an explicit leading is the
      // only way back to the role screen.
      onBack: () => context.read<AppState>().resetRole(),
      body: LazyTabStack(
        index: _index,
        builders: [
          () => const TeacherDashboard(),
          () => const FilesScreen(sharing: true),
          () => const SettingsScreen(roleLabel: 'Teacher'),
        ],
      ),
    );
  }
}