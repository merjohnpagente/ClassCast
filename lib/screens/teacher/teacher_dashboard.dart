import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/classroom_session.dart';
import '../../providers/app_state.dart';
import '../../providers/session_provider.dart';
import '../../services/network_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/formatters.dart';
import '../../widgets/motion.dart';
import '../../widgets/session_actions_sheet.dart';
import '../../widgets/qr_card.dart';
import '../../widgets/state_cards.dart';
import '../../widgets/ui_kit.dart';
import '../common/network_help_screen.dart';
import 'create_session_screen.dart';
import 'presentation_screen.dart';
import 'students_screen.dart';

/// Teacher dashboard: one create button, the network address students join on,
/// and the session list with the live session at the top.
class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key});

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
    // Same reason the settings tab needs a deadline: a platform channel that
    // never answers left the dashboard reading "Checking network…" for good.
    // Cancelled on dispose so the deadline never outlives the screen.
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

  void _openCreateSession() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateSessionScreen()),
    );
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
        padding: EdgeInsets.only(bottom: 24),
        children: [
          // One create button, at the top, in the same place every time. It
          // used to be duplicated by an action inside the empty state, so the
          // empty dashboard shouted the same instruction twice and neither
          // spot felt canonical.
          FadeIn(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.icon(
                onPressed: _openCreateSession,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Create New Session'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FadeIn(
            delay: Motion.stagger(1),
            child: _networkRow(theme),
          ),
          if (_checkMessage != null)
            FadeIn(child: _connectionCheck(theme)),
          if (active != null && sessions.reachabilityHintDue)
            FadeIn(child: _reachabilityHint(theme, active)),
          AppSectionTitle('My Sessions', trailing: _sessionCount(sessions)),
          if (active != null) ...[
            FadeIn(
              delay: Motion.stagger(2),
              child: _ActiveSessionCard(
                session: active,
                connectedCount: sessions.connectedCount,
                raisedHands: sessions.raisedHands.length,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TeacherPresentationScreen(),
                  ),
                ),
                onQr: () => _showQrSheet(context, active),
                onStudents: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StudentsScreen()),
                ),
                onEnd: () => _confirmEnd(context, sessions),
              ),
            ),
            const SizedBox(height: 10),
          ],
          FadeIn(
            delay: Motion.stagger(3),
            child: const TeacherDashboardSessionList(),
          ),
        ],
      ),
    );
  }

  String? _sessionCount(SessionProvider sessions) {
    final total = sessions.recent.length;
    if (total == 0) return null;
    return '$total';
  }

  /// The address students join on, in one line, plus the two things a teacher
  /// needs to know about it: is it reachable, and how do I fix it if not.
  Widget _networkRow(ThemeData theme) {
    final port = context.read<AppState>().serverPort;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const AppIconTile(
              icon: Icons.wifi,
              color: AppColors.success,
              background: AppColors.successBg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _probingIp
                        ? 'Checking network…'
                        : _ip.isEmpty
                            ? 'No local network yet'
                            : '$_ip:$port',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    'Students join over Wi-Fi or hotspot',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
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
            IconButton(
              tooltip: 'Connection guide',
              icon: const Icon(Icons.help_outline, color: AppColors.primary),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NetworkHelpScreen(isTeacher: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Honest one-liner under the network card: either it works, or exactly
  /// what to change.
  Widget _connectionCheck(ThemeData theme) {
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
              _checkMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ok ? AppColors.success : AppColors.inkSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The honest answer to "why is nobody joining?".
  ///
  /// The teacher's own check cannot see client isolation: a self-check to
  /// this phone's address connects over the loopback route no matter what the
  /// Wi-Fi does to student traffic. So this is a time-based nudge, not a fake
  /// verdict — a live session that no student has reached after a minute is
  /// very likely sitting behind a network that blocks device-to-device
  /// traffic, and the surest fix is the teacher's own hotspot.
  Widget _reachabilityHint(ThemeData theme, ClassroomSession active) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        color: AppColors.warningBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.warning),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.wifi_tethering_off,
                      size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No student has reached this session yet',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'School and guest Wi-Fi often block devices from '
                          'seeing each other. If students are on it and cannot '
                          'join, turn on your phone\'s hotspot and show the '
                          'new QR code — that is the surest fix.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _showQrSheet(context, active),
                    icon: const Icon(Icons.qr_code_2, size: 18),
                    label: const Text('Show QR'),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const NetworkHelpScreen(isTeacher: true),
                      ),
                    ),
                    icon: const Icon(Icons.help_outline, size: 18),
                    label: const Text('Guide'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ending a session drops every student on the floor. One tap should not be
  /// enough for that, and the dashboard's End button sits right next to a
  /// card a teacher taps constantly.
  void _confirmEnd(BuildContext context, SessionProvider sessions) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End session?'),
        content: const Text(
          'Students will be disconnected and the join code stops working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.of(ctx).pop();
              sessions.endSession();
            },
            child: const Text('End session'),
          ),
        ],
      ),
    );
  }

  /// Shows the real, scannable QR code for a live session.
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

/// The live session, drawn as the design's "Students 12 Connected" card: the
/// document being shown, the room size, and the two controls a teacher
/// actually reaches for mid-lesson.
class _ActiveSessionCard extends StatelessWidget {
  final ClassroomSession session;
  final int connectedCount;
  final int raisedHands;
  final VoidCallback onTap;
  final VoidCallback onQr;
  final VoidCallback onStudents;
  final VoidCallback onEnd;

  const _ActiveSessionCard({
    required this.session,
    required this.connectedCount,
    required this.raisedHands,
    required this.onTap,
    required this.onQr,
    required this.onStudents,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  AppIconTile(
                    icon: session.documentName == null
                        ? Icons.meeting_room_outlined
                        : Icons.description_outlined,
                    size: 44,
                    iconSize: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          session.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          session.documentName == null
                              ? 'Live · no document shared'
                              : session.documentName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  LiveDot(active: session.isActive),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          AppListRow(
            icon: Icons.people,
            title: connectedCount == 0
                ? 'Waiting for students'
                : '$connectedCount connected',
            subtitle: raisedHands == 0
                ? 'Share the QR code so they can join'
                : '$raisedHands hand(s) raised',
            trailing: const AppChevron(),
            onTap: onStudents,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onQr,
                    icon: const Icon(Icons.qr_code_2, size: 18),
                    label: const Text('QR code'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEnd,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('End'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The session list. The active session is rendered by the dashboard above,
/// so this is the history underneath it.
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: EmptyState(
          icon: Icons.history,
          title: 'No past classes yet',
          subtitle: 'Classes you teach show up here, ready to revive.',
        ),
      );
    }
    // Every recent session is a menu: revive it, edit it, or delete it. This
    // is the teacher's way back into yesterday's class without starting over.
    final shown = items.take(8).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            AppListRow(
              icon: Icons.meeting_room_outlined,
              title: shown[i].name,
              subtitle: shown[i].subject.isEmpty
                  ? formatDateTime(shown[i].createdAt)
                  : '${shown[i].subject} · '
                      '${formatDateTime(shown[i].createdAt)}',
              trailing: LiveDot(active: shown[i].isActive),
              onTap: () => showSessionActions(context, shown[i]),
            ),
          ],
        ],
      ),
    );
  }
}