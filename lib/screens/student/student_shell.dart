import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../providers/sync_provider.dart';
import '../../services/classcast_client.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/chrome_toggle.dart';
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

  /// Clears the app bar and the bottom navigation away while the student is
  /// looking at the slide, so the page is the only thing on the phone.
  final ChromeController _chrome = ChromeController();

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
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

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

    // Only the viewer hides chrome: the join and connection tabs are chrome
    // themselves, so clearing them would leave nothing behind.

    // A session that ends while the student is looking at a hidden slide would
    // otherwise leave the flag set, and the next session would come up blank.
    // Restored after the frame, because notifying mid-build rebuilds the tree.
    if (_index == 1 && !presenting && _chrome.hidden) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _chrome.show();
      });
    }

    return ChromeToggleScope(
      controller: _chrome,
      // The controller belongs to this state, so reading it up here would not
      // register a rebuild. The builder below is where the flag is read.
      child: ListenableBuilder(
        listenable: _chrome,
        builder: (context, _) {
          final hideChrome = _index == 1 && presenting && _chrome.hidden;
          return AppScaffold(
            title: title,
            destinations: _destinations,
            currentIndex: _index,
            showChrome: !hideChrome,
            onNavigate: (i) {
              // Leaving the viewer restores the navigation, so the student is
              // never stranded on a hidden screen they cannot get out of.
              if (i != 1) _chrome.show();
              setState(() => _index = i);
            },
            // Back from the Join (QR / session ID) flow returns to role
            // selection. Leaving first matters: otherwise the socket and
            // participant entry would outlive the screen.
            onBack: () async {
              _chrome.show();
              if (joined) await sync.leave();
              if (context.mounted) {
                context.read<AppState>().resetRole();
              }
            },
            actions: [
              if (_index == 1 && presenting) const ChromeAppBarAction(),
              if (joined)
                TextButton.icon(
                  onPressed: () async {
                    _chrome.show();
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
                // Goes to the viewer tab unconditionally. It used to read
                // `presenting` — a local from the build that happened before
                // the tap — so a student who joined a class that already had a
                // document sat on the join screen with a green "live" chip
                // until they navigated by hand. The viewer tab renders either
                // the document or the waiting room, so it is the right place to
                // land either way.
                () => JoinScreen(
                      onJoined: () => setState(() => _index = 1),
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
        },
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
