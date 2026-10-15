import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/classroom_session.dart';
import '../../providers/app_state.dart';
import '../../providers/session_provider.dart';
import '../../services/network_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/motion.dart';
import '../../widgets/session_actions_sheet.dart';
import '../../widgets/qr_card.dart';
import '../../widgets/session_card.dart';
import '../../widgets/state_cards.dart';
import '../../widgets/status_bits.dart';
import '../common/network_help_screen.dart';
import 'create_session_screen.dart';
import 'presentation_screen.dart';
import 'students_screen.dart';

/// Teacher dashboard: welcome, create button, active session,
/// recent sessions, students, documents, network + QR shortcuts.
class TeacherDashboard extends StatefulWidget {
  final VoidCallback onOpenSessions;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenSettings;

  const TeacherDashboard({
    super.key,
    required this.onOpenSessions,
    required this.onOpenFiles,
    required this.onOpenSettings,
  });

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  String _ip = '';
  bool _probingIp = true;

  /// Result of the teacher's last "can students reach me?" check.
  bool? _reachable;
  String? _checkMessage;
  bool _checking = false;

  /// Pings the address that goes into the QR code, over the network rather
  /// than loopback: "my server is up" and "students can reach it" are
  /// different questions, and only one of them is ever on screen.
  Future<void> _checkConnection() async {
    setState(() {
      _checking = true;
      _reachable = null;
      _checkMessage = null;
    });
    final port = context.read<AppState>().serverPort;
    final sessions = context.read<SessionProvider>();
    final host = sessions.active?.hostIp.isNotEmpty == true
        ? sessions.active!.hostIp
        : _ip;
    final result = await NetworkService.checkHost(host: host, port: port);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _reachable = result.reachable;
      _checkMessage = result.message;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadIp();
  }

  Timer? _probe;

  @override
  void dispose() {
    _probe?.cancel();
    super.dispose();
  }

  Future<void> _loadIp() async {
    // Same reason as the settings tab: a platform channel that never answers
    // left the dashboard reading "Checking network…" indefinitely. Cancelled
    // on dispose so the deadline never outlives the screen.
    _probe?.cancel();
    _probe = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _probingIp = false);
    });
    final ip = await NetworkService().localIp();
    _probe?.cancel();
    _probe = null;
    if (!mounted) return;
    final sessions = context.read<SessionProvider>();
    setState(() {
      _ip = ip;
      _probingIp = false;
    });
    if (ip.isNotEmpty && sessions.active != null) {
      sessions.setNetwork(
          hostIp: ip, port: context.read<AppState>().serverPort);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = context.watch<SessionProvider>();
    final active = sessions.active;

    return RefreshIndicator(
      onRefresh: () async {
        await sessions.load();
        await _loadIp();
      },
      child: ListView(
        children: [
          Text('Welcome back',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              )),
          Text(
            'Start a class, share files, present.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const CreateSessionScreen()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Create New Session'),
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _networkCard(theme),
              _connectionCheck(context),
            ],
          ),
          const SectionHeader(title: 'Active session'),
          if (active == null)
            EmptyState(
              icon: Icons.meeting_room_outlined,
              title: 'No active session',
              subtitle:
                  'Create a session to get a QR code and joining address.',
              actionLabel: 'Create session',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const CreateSessionScreen()),
              ),
            )
          else
            SessionCard(
              session: active,
              connectedCount: sessions.connectedCount,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        const TeacherPresentationScreen()),
              ),
              onQr: () => _showQrSheet(context, active),
              onEnd: () => sessions.endSession(),
            ),
          SectionHeader(
            title: 'Quick actions',
            action: TextButton(
              onPressed: widget.onOpenSessions,
              child: const Text('All sessions'),
            ),
          ),
          GridView.count(
            crossAxisCount:
                MediaQuery.sizeOf(context).width >= 720 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              _quickAction(context,
                  icon: Icons.people,
                  label:
                      '${sessions.connectedCount} connected',
                  onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const StudentsScreen()),
                      )),
              _quickAction(context,
                  icon: Icons.folder,
                  label: 'Files',
                  onTap: widget.onOpenFiles),
              _quickAction(context,
                  icon: Icons.qr_code_2,
                  label: 'QR to join',
                  onTap: active == null
                      ? null
                      : () => _showQrSheet(context, active)),
              _quickAction(context,
                  icon: Icons.settings,
                  label: 'Settings',
                  onTap: widget.onOpenSettings),
            ],
          ),
          const SectionHeader(title: 'Recent sessions'),
          const TeacherDashboardSessionList(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _networkCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.wifi,
                  color: AppColors.success),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _probingIp
                        ? 'Checking network…'
                        : _ip.isEmpty
                            ? 'No local network yet'
                            : 'Hosting at $_ip:${context.read<AppState>().serverPort}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    'Students join over Wi-Fi or hotspot — no internet needed.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Can students reach me?',
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _reachable == true
                              ? Icons.check_circle
                              : Icons.network_check,
                          color: _reachable == true
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                  onPressed: _checking ? null : _checkConnection,
                ),
                Text(
                  'Check',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Connection guide',
              icon: const Icon(Icons.help_outline,
                  color: AppColors.primary),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        const NetworkHelpScreen(isTeacher: true)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Honest one-liner under the network card: either it works, or exactly
  /// what to change.
  Widget _connectionCheck(BuildContext context) {
    final message = _checkMessage;
    if (message == null) return const SizedBox.shrink();
    final ok = _reachable == true;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.info_outline,
            size: 18,
            color: ok ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ok ? AppColors.success : AppColors.inkSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction(BuildContext context,
      {required IconData icon,
      required String label,
      VoidCallback? onTap}) {
    final disabled = onTap == null;
    return Pressable(
      onTap: onTap,
      child: Card(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: disabled ? AppColors.muted : AppColors.primary),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: disabled ? AppColors.muted : AppColors.ink,
                )),
          ],
        ),
      ),
    );
  }

  /// Shows the real, scannable QR code for a live session.
  ///
  /// This used to print the raw join payload as text, which is useless in a
  /// classroom: students have to point a camera at it. The code is drawn large
  /// enough to scan from a student's desk.
  void _showQrSheet(BuildContext context, ClassroomSession active) {
    final address = active.joinAddress;
    final payload = NetworkService.qrPayload(
        host: active.hostIp, port: active.port, sessionId: active.id);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  active.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 12),
                if (active.hostIp.isEmpty)
                  // No LAN address yet: a QR without a host cannot be scanned,
                  // so say so instead of showing a dead code.
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.wifi_off,
                            size: 40, color: AppColors.warning),
                        SizedBox(height: 12),
                        Text(
                          'No network address yet',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Start the hotspot (or connect to classroom Wi-Fi) '
                          'so students can reach this phone.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  QrCard(
                    payload: payload,
                    address: address.isEmpty
                        ? 'Session ${active.id}'
                        : address,
                    sessionId: active.id,
                    size: 240,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Recent session list shared by dashboard + sessions tab.
class TeacherDashboardSessionList extends StatelessWidget {
  const TeacherDashboardSessionList({super.key});

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionProvider>();
    if (!sessions.isLoaded) {
      return const LoadingState(message: 'Loading sessions…');
    }
    final items =
        sessions.recent.where((s) => s.id != sessions.active?.id).toList();
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'No past classes yet',
        subtitle: 'Classes you teach show up here, ready to revive.',
      );
    }
    // Every recent session is a menu: revive it, edit it, or delete it. This
    // is the teacher's way back into yesterday's class without starting over.
    return Column(
      children: [
        for (final s in items.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            // SessionCard has its own tap handling; wrapping it in another
            // gesture detector would fire the action twice.
            child: SessionCard(
              session: s,
              onTap: () => showSessionActions(context, s),
            ),
          ),
      ],
    );
  }
}
