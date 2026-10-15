import 'package:flutter/material.dart';

import '../models/classroom_session.dart';
import '../providers/app_state.dart';
import '../providers/library_provider.dart';
import '../providers/session_provider.dart';
import '../services/network_service.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';
import '../utils/validators.dart';
import 'motion.dart';

/// Actions on one recent session: revive it, edit its details, or delete it.
///
/// Reviving keeps the **same session id**, so a QR code printed for that class
/// (or an id typed by hand) works again — the roster and the page start fresh,
/// and the document can be re-shared straight from the library.
class SessionActionsSheet extends StatefulWidget {
  final ClassroomSession session;

  const SessionActionsSheet({super.key, required this.session});

  @override
  State<SessionActionsSheet> createState() => _SessionActionsSheetState();
}

class _SessionActionsSheetState extends State<SessionActionsSheet> {
  final _form = GlobalKey<FormState>();
  late final _name =
      TextEditingController(text: widget.session.name);
  late final _subject =
      TextEditingController(text: widget.session.subject);
  late bool _anonymous = widget.session.allowAnonymous;
  late bool _download = widget.session.allowDownload;
  late bool _studentNav = widget.session.allowStudentNav;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final sessions = context.read<SessionProvider>();
    await sessions.updateSession(widget.session.copyWith(
      name: _name.text.trim(),
      subject: _subject.text.trim(),
      allowAnonymous: _anonymous,
      allowDownload: _download,
      allowStudentNav: _studentNav,
    ));
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session updated')),
    );
  }

  Future<void> _revive() async {
    setState(() => _busy = true);
    final app = context.read<AppState>();
    final sessions = context.read<SessionProvider>();
    // Re-pick the address: the old one belongs to whatever network the session
    // ran on, and reviving usually happens on a different one.
    final ip = await NetworkService().localIp();
    if (!mounted) return;
    final document = _documentToReshare();
    final revived = await sessions.reviveSession(
      widget.session,
      hostIp: ip,
      port: app.serverPort,
      document: document,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
    if (revived == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(revived.id == widget.session.id
            ? 'Session ${revived.id} is live again'
            : 'Session started as ${revived.id}'),
      ),
    );
  }

  /// The previously shared document, if the teacher still has it in the
  /// library and the file is still on the device.
  SharedDocument? _documentToReshare() {
    final name = widget.session.documentName;
    if (name == null || name.isEmpty) return null;
    final library = context.read<LibraryProvider>();
    final dot = name.lastIndexOf('.');
    final base = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
    for (final doc in library.items) {
      if (doc.extension == ext && doc.name.toLowerCase() == base.toLowerCase()) {
        return doc;
      }
    }
    return null;
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
          'This removes "${widget.session.name}" from your recent sessions. '
          'Files in your library are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await context.read<SessionProvider>().deleteSession(widget.session.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final document = _documentToReshare();
    final session = widget.session;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(session.id,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.muted,
                      letterSpacing: 1,
                    )),
                const SizedBox(height: 4),
                FadeIn(
                  child: Text('Session details',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  validator: Validators.sessionName,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Session name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _subject,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Subject (optional)',
                    prefixIcon: Icon(Icons.menu_book_outlined),
                  ),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Anonymous students'),
                  subtitle: const Text('No name needed to join'),
                  value: _anonymous,
                  onChanged: (v) => setState(() => _anonymous = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Allow downloads'),
                  subtitle: const Text('Students can save shared files'),
                  value: _download,
                  onChanged: (v) => setState(() => _download = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Students turn pages'),
                  subtitle: const Text('Otherwise they follow your page'),
                  value: _studentNav,
                  onChanged: (v) => setState(() => _studentNav = v),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save changes'),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'Bring this session back with the same code, so the QR or '
                  'ID your students already have keeps working.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
                if (document != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.description_outlined,
                          size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Re-shares ${document.name}.${document.extension}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _revive,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Revive session'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _delete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete session'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [SessionActionsSheet] for [session].
Future<void> showSessionActions(
    BuildContext context, ClassroomSession session) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ContentWidth(
      maxWidth: 520,
      child: SessionActionsSheet(session: session),
    ),
  );
}