import 'package:flutter/material.dart';

import '../../widgets/app_scaffold.dart';
import 'create_session_screen.dart';
import 'teacher_dashboard.dart';
import '../common/files_screen.dart';
import '../common/settings_screen.dart';
import 'presentation_screen.dart';

/// Teacher navigation shell. Mobile: bottom nav.
/// Desktop: sidebar. Tabs: Home, Sessions, Files, Settings.
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
        label: 'Sessions',
        icon: Icons.meeting_room_outlined,
        selectedIcon: Icons.meeting_room),
    AppDestination(
        label: 'Files',
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder),
    AppDestination(
        label: 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _destinations[_index].label,
      destinations: _destinations,
      currentIndex: _index,
      onNavigate: (i) => setState(() => _index = i),
      actions: [
        IconButton(
          tooltip: 'Present now',
          icon: const Icon(Icons.present_to_all),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const TeacherPresentationScreen()),
          ),
        ),
      ],
      body: IndexedStack(
        index: _index,
        children: [
          TeacherDashboard(
            onOpenSessions: () => setState(() => _index = 1),
            onOpenFiles: () => setState(() => _index = 2),
            onOpenSettings: () => setState(() => _index = 3),
          ),
          const _SessionsTab(),
          const FilesScreen(sharing: true),
          const SettingsScreen(roleLabel: 'Teacher'),
        ],
      ),
    );
  }
}

class _SessionsTab extends StatelessWidget {
  const _SessionsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const CreateSessionScreen()),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Create New Session'),
        ),
        const SizedBox(height: 12),
        const TeacherDashboardSessionList(),
      ],
    );
  }
}
