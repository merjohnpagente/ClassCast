import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/app_state.dart';
import '../../providers/session_provider.dart';
import '../../services/network_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../utils/validators.dart';
import '../../widgets/motion.dart';
import '../../widgets/qr_card.dart';
import '../../widgets/status_bits.dart';
import 'presentation_screen.dart';

/// Create a classroom session: name, subject, access settings.
/// After Start: session ID + QR + address + copy + End.
class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'Introduction to Physics');
  final _subject = TextEditingController();
  bool _allowAnonymous = true;
  bool _allowDownload = false;
  bool _allowStudentNav = false;
  bool _starting = false;
  String? _sessionId;

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _starting = true;
    });
    final app = context.read<AppState>();
    final sessions = context.read<SessionProvider>();
    final ip = await NetworkService().localIp();
    if (!mounted) return;
    final session = await sessions.createSession(
      name: _name.text,
      subject: _subject.text,
      hostIp: ip,
      port: app.serverPort,
      allowAnonymous: _allowAnonymous,
      allowDownload: _allowDownload,
      allowStudentNav: _allowStudentNav,
    );
    if (!mounted) return;
    setState(() {
      _starting = false;
      _sessionId = session.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = context.watch<SessionProvider>();
    final active = sessions.active;
    final created = _sessionId != null && active != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Session')),
      body: ContentWidth(
        maxWidth: 640,
        child: ListView(
          padding: EdgeInsets.all(context.pagePadding),
          children: [
            if (!created) ...[
              Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Session name',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _name,
                      validator: Validators.sessionName,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Introduction to Physics',
                        prefixIcon: Icon(Icons.meeting_room_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Subject (optional)',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _subject,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: 'Physics',
                        prefixIcon: Icon(Icons.book_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const SectionHeader(title: 'Access settings'),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Allow anonymous joining'),
                            subtitle: const Text(
                                'Students can join without a name'),
                            value: _allowAnonymous,
                            onChanged: (v) => setState(
                                () => _allowAnonymous = v),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text('Allow downloads'),
                            subtitle: const Text(
                                'Students can save the shared file'),
                            value: _allowDownload,
                            onChanged: (v) => setState(
                                () => _allowDownload = v),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title:
                                const Text('Let students turn pages'),
                            subtitle: const Text(
                                'Off = teacher controls every screen'),
                            value: _allowStudentNav,
                            onChanged: (v) => setState(
                                () => _allowStudentNav = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _starting ? null : _start,
                      child: _starting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white),
                            )
                          : const Text('Start Session'),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Works fully offline — no cloud account needed.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // The classroom server lives on this phone. If it is not
              // running, no student can join no matter how good the Wi-Fi is,
              // so it is stated plainly instead of hidden behind a green tick.
              if (!sessions.hostingLocally)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    color: AppColors.warningBg,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: AppColors.warning),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Students cannot connect',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Port ${active.port} is busy. Change the port in '
                            'Settings, then start a new session.',
                            style: const TextStyle(
                                color: AppColors.inkSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Card(
                color: AppColors.successBg,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text('Session live',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Text('Session ID: ${active.id}',
                                style: const TextStyle(
                                    color: AppColors.inkSecondary)),
                            if (sessions.hostAddress.isNotEmpty)
                              Text(
                                'Serving ${sessions.hostAddress}',
                                style: const TextStyle(
                                    color: AppColors.inkSecondary,
                                    fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy session ID',
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: active.id));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                                    content: Text(
                                        'Session ID copied')));
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              QrCard(
                payload: NetworkService.qrPayload(
                    host: active.hostIp,
                    port: active.port,
                    sessionId: active.id),
                address: active.joinAddress.isEmpty
                    ? 'Start hotspot to show the address'
                    : active.joinAddress,
                sessionId: active.id,
                // Large enough for students to scan from their desks.
                size: 220,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context)
                    .pushReplacement(MaterialPageRoute(
                        builder: (_) =>
                            const TeacherPresentationScreen())),
                icon: const Icon(Icons.present_to_all),
                label: const Text('Open Presentation'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await sessions.endSession();
                  if (context.mounted) {
                    setState(() => _sessionId = null);
                  }
                },
                icon: const Icon(Icons.stop),
                label: const Text('End Session'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side:
                      const BorderSide(color: AppColors.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
