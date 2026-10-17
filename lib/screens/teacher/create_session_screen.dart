import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/classroom_session.dart';
import '../../providers/app_state.dart';
import '../../providers/session_provider.dart';
import '../../services/host/classcast_host.dart';
import '../../services/network_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../utils/validators.dart';
import '../../widgets/motion.dart';
import '../../widgets/qr_card.dart';
import '../../widgets/ui_kit.dart';
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
    // A throw from createSession used to leave `_starting` true for good, so
    // the button stayed a disabled spinner and the teacher had no way forward.
    try {
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start the session: $e')),
      );
    }
  }

  /// Ending a session drops every student. One tap should not be enough.
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
            onPressed: () async {
              Navigator.of(ctx).pop();
              await sessions.endSession();
              if (context.mounted) {
                setState(() => _sessionId = null);
              }
            },
            child: const Text('End session'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionProvider>();
    final active = sessions.active;

return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Create Session')),
      body: ContentWidth(
        maxWidth: 520,
        // The null test has to live in the conditional itself: stashing it in a
        // bool does not promote `active`, and every field below is then read
        // off a nullable.
        child: (_sessionId != null && active != null)
            ? LayoutBuilder(
                builder: (context, constraints) {
                  // One column on a phone, two where there is room for them:
                  // the code is what a room looks at and the buttons are what
                  // a teacher reaches for, and side by side they both stop
                  // pushing the rest of the page below the fold.
                  final twoColumns = constraints.maxWidth >= 460;
                  final padding = EdgeInsets.fromLTRB(
                    context.pagePadding,
                    0,
                    context.pagePadding,
                    32,
                  );
                  final qr = QrCard(
                    payload: NetworkService.qrPayload(
                        host: active.hostIp,
                        port: active.port,
                        sessionId: active.id,
                        // Both networks in one code: the hotspot address and
                        // the Wi-Fi address, whichever the session is not
                        // already using.
                        altHosts: sessions.alternateAddresses),
                    address: active.joinAddress.isEmpty
                        ? 'Turn on your hotspot to get an address'
                        : active.joinAddress,
                    sessionId: active.id,
                    // Fills the width it is given, within limits: a code too
                    // small to scan from a desk, or wider than the phone, are
                    // both this page's problem and neither is a fixed number.
                    size: (constraints.maxWidth - 64).clamp(150.0, 280.0),
                  );
                  final actions = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context)
                            .pushReplacement(MaterialPageRoute(
                                builder: (_) =>
                                    const TeacherPresentationScreen())),
                        icon: const Icon(Icons.present_to_all, size: 20),
                        label: const Text('Show to class'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _confirmEnd(context, sessions),
                        icon: const Icon(Icons.stop, size: 20),
                        label: const Text('End Session'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          foregroundColor: AppColors.error,
                          side: BorderSide(color: AppColors.error),
                        ),
                      ),
                    ],
                  );

                  return ListView(
                    padding: padding,
                    children: [
                      _liveHeader(context, sessions, active),
                      const SizedBox(height: 4),
                      if (twoColumns)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(child: qr),
                            const SizedBox(width: 16),
                            Expanded(child: actions),
                          ],
                        )
                      else ...[
                        qr,
                        const SizedBox(height: 20),
                        actions,
                      ],
                    ],
                  );
                },
              )
            : _formView(context),
      ),
    );
  }

  /// Two fields, one primary button, and the access options tucked underneath
  /// — the shape the design draws, without losing the three settings the
  /// classroom actually runs on.
  Widget _formView(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide enough for the fields and the access options side by side, so a
        // tablet does not show a phone's layout stretched across it.
        final twoColumns = constraints.maxWidth >= 560;
        final fields = FadeIn(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppFieldLabel('Session Name'),
                TextFormField(
                  controller: _name,
                  validator: Validators.sessionName,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Class 101'),
                ),
                const SizedBox(height: 16),
                const AppFieldLabel('Subject (optional)'),
                TextFormField(
                  controller: _subject,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Physics'),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _starting ? null : _start,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                  ),
                  child: _starting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text('Start Session'),
                ),
              ],
            ),
          ),
        );
        final access = FadeIn(
          delay: Motion.stagger(1),
          child: _accessRow(theme),
        );

        return ListView(
          padding: EdgeInsets.fromLTRB(
            context.pagePadding,
            8,
            context.pagePadding,
            32,
          ),
          children: [
            if (twoColumns)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: fields),
                    const SizedBox(width: 24),
                    Expanded(child: access),
                  ],
                ),
              )
            else ...[
              fields,
              access,
              const SizedBox(height: 24),
              Text(
                'No internet needed — students join over your hotspot or the '
                'same Wi-Fi.',
                textAlign: TextAlign.center,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Green banner, or an honest warning when the classroom server is not up.
  ///
  /// The host lives on this phone. If it is not running, no student can join
  /// no matter how good the Wi-Fi is, so that is stated plainly instead of
  /// hidden behind a green tick.
  Widget _liveHeader(
      BuildContext context, SessionProvider sessions, ClassroomSession active) {
    final theme = Theme.of(context);
    if (!sessions.hostingLocally) {
      return Card(
        color: AppColors.warningBg,
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                   Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Students cannot connect',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                // The host used to answer false for "port busy", "no
                // permission" and "no network" alike, so the only advice
                // given was sometimes the wrong one.
                ClasscastHost.instance.lastStartError ??
                    'Port ${active.port} is busy. Change the port in '
                        'Settings, then start a new session.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      color: AppColors.successBg,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Class is live',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Join code ${active.id}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (sessions.hostAddress.isNotEmpty)
                    Text(
                      'Serving ${sessions.hostAddress}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy join code',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: active.id));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(
                          content: Text('Session ID copied')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// The three access options as one wrapping row of chips.
  ///
  /// They were three SwitchListTiles with subtitles: about 220px of card for
  /// three booleans, taller than the two text fields above it and louder than
  /// the action it configures.
  Widget _accessRow(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionTitle('Access'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AccessChip(
              icon: Icons.person_off_outlined,
              label: 'Anonymous',
              hint: 'Students can join without a name',
              value: _allowAnonymous,
              onChanged: (v) => setState(() => _allowAnonymous = v),
            ),
            _AccessChip(
              icon: Icons.download_outlined,
              label: 'Downloads',
              hint: 'Students can save the shared file',
              value: _allowDownload,
              onChanged: (v) => setState(() => _allowDownload = v),
            ),
            _AccessChip(
              icon: Icons.swipe_right_alt_outlined,
              label: 'Student pages',
              hint: 'Students turn pages instead of following you',
              value: _allowStudentNav,
              onChanged: (v) => setState(() => _allowStudentNav = v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _accessHint,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }

  /// One plain sentence for whatever the chips currently allow, so a teacher
  /// never has to open anything to know what the class is set to.
  String get _accessHint {
    final allowed = <String>[
      if (_allowAnonymous) 'join without a name',
      if (_allowDownload) 'save the shared file',
      if (_allowStudentNav) 'turn pages themselves',
    ];
    if (allowed.isEmpty) {
      return 'Students must give a name and can only follow your screen.';
    }
    return 'Students can ${allowed.join(', ')}.';
  }
}

/// One access toggle, sized to sit shoulder to shoulder with its siblings.
///
/// A switch has to own a whole row to be legible; a chip does not, so three
/// of them fit the width of a phone in one line and leave the primary action
/// as the only thing on screen that competes for a thumb.
class _AccessChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _AccessChip({
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: hint,
      child: FilterChip(
        selected: value,
        onSelected: onChanged,
        // The selected tint plus the label colour already say "on"; a second
        // checkmark would just be noise.
        showCheckmark: false,
        avatar: Icon(
          icon,
          size: 15,
          color: value ? AppColors.primary : AppColors.muted,
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: value ? AppColors.primary : AppColors.inkSecondary,
          ),
        ),
        selectedColor: AppColors.primarySoft,
        backgroundColor: AppColors.surface,
        side: BorderSide(
          color: value
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.border,
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }
}