import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../providers/session_provider.dart';
import '../../services/network_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/motion.dart';
import '../../widgets/status_bits.dart';
import 'network_help_screen.dart';

/// Settings: network info, server status, IP, session prefs,
/// sync prefs, downloads, about, help. Students see a reduced set.
class SettingsScreen extends StatefulWidget {
  final String roleLabel;

  const SettingsScreen({super.key, required this.roleLabel});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _ip = '';
  String? _wifi;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final net = NetworkService();
    final ip = await net.localIp();
    final wifi = await net.wifiName();
    if (!mounted) return;
    setState(() {
      _ip = ip;
      _wifi = wifi;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = context.watch<AppState>();
    final sessions = context.watch<SessionProvider>();
    final isTeacher = widget.roleLabel == 'Teacher';

    return ContentWidth(
      maxWidth: 640,
      child: ListView(
      children: [
        FadeIn(child: const SectionHeader(title: 'Network')),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.wifi,
                    color: AppColors.primary),
                title: const Text('Local network'),
                subtitle: Text(_loading
                    ? 'Checking…'
                    : _wifi ?? 'Not connected'),
                trailing: _ip.isEmpty
                    ? StatusChip.offline()
                    : StatusChip.connected(),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.router_outlined,
                    color: AppColors.primary),
                title: const Text('This device IP'),
                subtitle: Text(_loading
                    ? 'Checking…'
                    : _ip.isEmpty
                        ? 'Unavailable — join Wi-Fi or hotspot'
                        : '$_ip:${app.serverPort}'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.help_outline,
                    color: AppColors.primary),
                title: const Text('Connection guide'),
                trailing:
                    const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => NetworkHelpScreen(
                          isTeacher: isTeacher)),
                ),
              ),
            ],
          ),
        ),
        if (isTeacher) ...[
          const SectionHeader(title: 'Classroom session'),
          Card(
            child: Column(
              children: [
                if (sessions.active != null) ...[
                  ListTile(
                    leading: const Icon(
                        Icons.meeting_room_outlined,
                        color: AppColors.primary),
                    title:
                        Text('Active: ${sessions.active!.name}'),
                    subtitle:
                        Text('ID ${sessions.active!.id}'),
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  leading: const Icon(Icons.download_outlined,
                      color: AppColors.primary),
                  title: const Text('Student downloads'),
                  subtitle: Text(sessions.active == null
                      ? 'Set when you create a session'
                      : sessions.active!.allowDownload
                          ? 'Allowed in this session'
                          : 'Blocked in this session'),
                ),
                SwitchListTile(
                  secondary:
                      const Icon(Icons.sync_outlined),
                  title: const Text('Pause synchronization'),
                  subtitle: const Text(
                      'Freeze student screens'),
                  value: sessions.active?.syncPaused ?? false,
                  onChanged: sessions.active == null
                      ? null
                      : (v) => sessions.setPaused(v),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Server'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns_outlined,
                  color: AppColors.primary),
              title: const Text('Local server port'),
              subtitle: Text('${app.serverPort}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editPort(context, app),
            ),
          ),
        ],
        const SectionHeader(title: 'About'),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.info_outline,
                    color: AppColors.primary),
                title: Text('ClassCast Offline'),
                subtitle: Text(
                    'Share. Present. Learn.\nVersion 1.0.0 · works without internet.'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined,
                    color: AppColors.primary),
                title: const Text('Help & troubleshooting'),
                trailing:
                    const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => NetworkHelpScreen(
                          isTeacher: isTeacher)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Students never see server internals or network controls.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _editPort(BuildContext context, AppState app) {
    final ctrl =
        TextEditingController(text: '${app.serverPort}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server port'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              hintText: '8080'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final p = int.tryParse(ctrl.text.trim());
              if (p != null && p >= 1024 && p <= 65535) {
                app.setServerPort(p);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
