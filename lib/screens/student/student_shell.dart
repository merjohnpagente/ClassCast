import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../providers/sync_provider.dart';
import '../../services/classcast_client.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/lazy_tab_stack.dart';
import '../common/network_help_screen.dart';
import '../common/settings_screen.dart';
import 'join_screen.dart';
import 'viewer_screen.dart';
import 'waiting_screen.dart';

/// Simple student navigation: Join, Viewer, Connection.
/// Teacher controls are never shown here.
class StudentShell extends StatefulWidget {
  const StudentShell({super.key});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _index = 0;

  static const _destinations = [
    AppDestination(
        label: 'Join',
        icon: Icons.login_outlined,
        selectedIcon: Icons.login),
    AppDestination(
        label: 'Viewer',
        icon: Icons.menu_book_outlined,
        selectedIcon: Icons.menu_book),
    AppDestination(
        label: 'Connection',
        icon: Icons.wifi_outlined,
        selectedIcon: Icons.wifi),
  ];

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final joined = sync.link == LinkState.live ||
        sync.link == LinkState.reconnecting;
    if (joined) sync.bind();
    final presenting =
        joined && sync.snapshot?.documentId != null;

    // The design titles the viewer with the class the student is actually in,
    // not with the word "Viewer".
    final title = _index == 1 && joined
        ? (sync.snapshot?.name ?? _destinations[_index].label)
        : _destinations[_index].label;

    return AppScaffold(
      title: title,
      destinations: _destinations,
      currentIndex: _index,
      onNavigate: (i) => setState(() => _index = i),
      // Back from the Join (QR / session ID) flow returns to role selection.
      // Leaving first matters: otherwise the socket and participant entry
      // would outlive the screen.
      onBack: () async {
        if (joined) await sync.leave();
        if (context.mounted) {
          context.read<AppState>().resetRole();
        }
      },
      actions: [
        if (joined)
          TextButton.icon(
            onPressed: () async {
              await sync.leave();
              if (context.mounted) setState(() => _index = 0);
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Leave'),
          ),
      ],
      body: LazyTabStack(
        index: _index,
        builders: [
          () => JoinScreen(
                onJoined: () =>
                    setState(() => _index = presenting ? 1 : _index),
              ),
          () => presenting
              ? const StudentViewerScreen()
              : StudentWaitingScreen(
                  onLeave: () => setState(() => _index = 0),
                ),
          () => const _StudentConnectionTab(),
        ],
      ),
    );
  }
}

class _StudentConnectionTab extends StatelessWidget {
  const _StudentConnectionTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const NetworkHelpBody(),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) =>
                    const SettingsScreen(roleLabel: 'Student')),
          ),
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Connection settings'),
        ),
      ],
    );
  }
}
