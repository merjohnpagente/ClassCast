import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/app_state.dart';
import '../../providers/session_provider.dart';
import '../../services/network_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/app_version.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui_kit.dart';
import 'network_help_screen.dart';

/// Settings: network info, server status, IP, session prefs, about, help.
/// Students see a reduced set.
class SettingsScreen extends StatefulWidget {
  final String roleLabel;

  const SettingsScreen({super.key, required this.roleLabel});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _githubUser = 'merjohnpagente';

  /// Spaced the way GCash displays it, so it can be read off the screen and
  /// typed into a wallet without guessing the grouping.
  static const _gcashNumber = '0915 043 5696';

  static const _gcashDigits = '09150435696';

  String _ip = '';
  String? _wifi;
  bool _loading = true;

  /// Opening an external link must never be able to crash the settings page:
  /// a phone with no browser, or a browser that refuses the intent, is normal
  /// enough that the user gets a sentence instead of a red screen.
  Future<void> _openGithub(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.parse('https://github.com/$_githubUser');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('launchUrl returned false');
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the browser.')),
      );
    }
  }

  Future<void> _copyGcash(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _gcashDigits));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('GCash number copied — $_gcashNumber')),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
    // The version is read off the build once, then the row asks for it again.
    unawaited(AppVersion.load().then((_) {
      if (mounted) setState(() {});
    }));
  }

  Future<void> _load() async {
    final net = NetworkService();
    // The plugin answers through a platform channel, and a channel that never
    // answers left this tab on "Checking…" for good. A deadline turns that into
    // an honest "not available" instead of an eternal spinner — and it is
    // cancelled on dispose so it never outlives the screen.
    _probe?.cancel();
    _probe = Timer(_networkTimeout, () {
      if (!mounted) return;
      setState(() => _loading = false);
    });
    final ip = await net.localIp();
    final wifi = await net.wifiName();
    _probe?.cancel();
    _probe = null;
    if (!mounted) return;
    setState(() {
      _ip = ip;
      _wifi = wifi;
      _loading = false;
    });
  }

  Timer? _probe;
  static const _networkTimeout = Duration(seconds: 4);

  /// Light or dark, per device. Following the phone is the default because a
  /// classroom in the evening and a phone handed out in the morning should
  /// not need different taps.
  void _pickTheme(BuildContext context, AppState app) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Theme'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              ListTile(
                leading: Icon(switch (mode) {
                  ThemeMode.system => Icons.brightness_auto_outlined,
                  ThemeMode.light => Icons.light_mode_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                }),
                title: Text(switch (mode) {
                  ThemeMode.system => 'Follow the phone',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                }),
                trailing: app.themeMode == mode
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onTap: () {
                  app.setThemeMode(mode);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _probe?.cancel();
    super.dispose();
  }

  void _editPort(BuildContext context, AppState app) {
    final ctrl = TextEditingController(text: '${app.serverPort}');
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Server port'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: '8080',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final p = int.tryParse(ctrl.text.trim());
                // Closing on a bad value told the teacher nothing about why
                // their change was ignored.
                if (p == null || p < 1024 || p > 65535) {
                  setInner(() => error = 'Enter a port between 1024 and 65535.');
                  return;
                }
                app.setServerPort(p);
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ).whenComplete(ctrl.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final app = context.watch<AppState>();
    final sessions = context.watch<SessionProvider>();
    final isTeacher = widget.roleLabel == 'Teacher';
    final active = sessions.active;
    final online = _ip.isNotEmpty;

    void openHelp() => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NetworkHelpScreen(isTeacher: isTeacher),
          ),
        );

    return ContentWidth(
      maxWidth: 560,
      child: ListView(
        padding: EdgeInsets.only(bottom: 24),
        children: [
          const AppSectionTitle('Network'),
          AppListGroup(
            rows: [
              AppListRow(
                icon: Icons.wifi,
                title: 'Local network',
                subtitle: _loading
                    ? 'Checking…'
                    : _wifi ?? (online ? 'Connected' : 'Not connected'),
                trailing: online
                    ? const LiveDot(active: true)
                    : const LiveDot(active: false),
              ),
              AppListRow(
                icon: Icons.router_outlined,
                title: 'This device IP',
                subtitle: _loading
                    ? 'Checking…'
                    : online
                        ? '$_ip:${app.serverPort}'
                        : 'Unavailable — join Wi-Fi or hotspot',
              ),
              AppListRow(
                icon: Icons.help_outline,
                title: 'Connection guide',
                trailing: const AppChevron(),
                onTap: openHelp,
              ),
            ],
          ),
          const AppSectionTitle('Appearance'),
          AppListGroup(
            rows: [
              AppListRow(
                icon: switch (app.themeMode) {
                  ThemeMode.system => Icons.brightness_auto_outlined,
                  ThemeMode.light => Icons.light_mode_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                },
                title: 'Theme',
                subtitle: switch (app.themeMode) {
                  ThemeMode.system => 'Follow the phone',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                },
                iconColor: AppColors.secondary,
                iconBackground: AppColors.secondarySoft,
                trailing: const AppChevron(),
                onTap: () => _pickTheme(context, app),
              ),
            ],
          ),
          if (isTeacher) ...[
            const AppSectionTitle('Classroom session'),
            AppListGroup(
              rows: [
                if (active != null)
                  AppListRow(
                    icon: Icons.meeting_room_outlined,
                    title: active.name,
                    subtitle: 'ID ${active.id}',
                    trailing: LiveDot(active: active.isActive),
                  ),
                AppListRow(
                  icon: Icons.shield_outlined,
                  title: 'Session security',
                  subtitle: active == null
                      ? 'Set when you create a session'
                      : active.allowAnonymous
                          ? 'Students may join without a name'
                          : 'Students must give a name',
                  iconColor: AppColors.secondary,
                  iconBackground: AppColors.secondarySoft,
                ),
                AppListRow(
                  icon: Icons.download_outlined,
                  title: 'Student downloads',
                  subtitle: active == null
                      ? 'Set when you create a session'
                      : active.allowDownload
                          ? 'Allowed in this session'
                          : 'Blocked in this session',
                ),
                AppListRow(
                  icon: Icons.sync_outlined,
                  title: 'Pause synchronization',
                  subtitle: 'Freeze student screens',
                  trailing: Switch(
                    value: active?.syncPaused ?? false,
                    onChanged: active == null
                        ? null
                        : (v) => sessions.setPaused(v),
                  ),
                  onTap: active == null
                      ? null
                      : () => sessions.setPaused(!(active.syncPaused)),
                ),
                AppListRow(
                  icon: Icons.dns_outlined,
                  title: 'Local server port',
                  subtitle: '${app.serverPort}',
                  trailing: Icon(Icons.edit_outlined,
                      size: 20, color: AppColors.muted),
                  onTap: () => _editPort(context, app),
                ),
              ],
            ),
          ],
          const AppSectionTitle('About'),
          AppListGroup(
            rows: [
              const AppListRow(
                icon: Icons.info_outline,
                title: 'ClassCast Offline',
                subtitle: 'Share. Present. Learn. Works without internet.',
              ),
              // The build that is installed, read from the build rather than
              // typed in here. It is the first thing anyone asks for when
              // something is not working, and a hardcoded number is right only
              // until the next release.
              AppListRow(
                icon: Icons.numbers_outlined,
                title: 'Version',
                subtitle: AppVersion.isLoaded
                    ? 'v${AppVersion.label}'
                    : 'Reading…',
                trailing: AppVersion.isLoaded
                    ? IconButton(
                        tooltip: 'Copy version',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(
                              ClipboardData(text: 'v${AppVersion.label}'));
                          messenger.showSnackBar(const SnackBar(
                              content: Text('Version copied')));
                        },
                      )
                    : null,
              ),
               AppListRow(
                icon: Icons.person_outline,
                title: 'Developed by MerjDev',
                iconColor: AppColors.secondary,
                iconBackground: AppColors.secondarySoft,
              ),
              AppListRow(
                leading: GitHubMark(
                  size: 20,
                  color: AppColors.ink,
                ),
                title: 'GitHub',
                subtitle: 'github.com/$_githubUser',
                iconColor: AppColors.ink,
                iconBackground: AppColors.surfaceSoft,
                trailing: const AppChevron(),
                onTap: () => _openGithub(context),
              ),
              // Tapping copies the number: there is no universal GCash deep
              // link, so the number travels and the teacher pastes it into
              // their wallet app.
              AppListRow(
                icon: Icons.coffee,
                title: 'Buy me a coffee',
                subtitle: 'GCash $_gcashNumber',
                iconColor: AppColors.warning,
                iconBackground: AppColors.warningBg,
                trailing: Icon(Icons.copy_all_outlined,
                    size: 20, color: AppColors.muted),
                onTap: () => _copyGcash(context),
              ),
              AppListRow(
                icon: Icons.bug_report_outlined,
                title: 'Help & troubleshooting',
                trailing: const AppChevron(),
                onTap: openHelp,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Students never see server internals or network controls.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}