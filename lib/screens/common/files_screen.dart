import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/doc_types.dart';
import '../../models/shared_document.dart';
import '../../providers/library_provider.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/document_card.dart';
import '../../widgets/motion.dart';
import '../../widgets/state_cards.dart';
import '../../widgets/ui_kit.dart';
import '../teacher/presentation_screen.dart';
import '../teacher/share_document_screen.dart';
import 'document_screen.dart';

/// Reusable document management: recent, search, filters,
/// empty / loading / error states. Grid on desktop, list on phones.
///
/// When [sharing] is true (teacher), tapping a row opens the share screen —
/// preview, share to the class, unshare — because that is the whole point of
/// the teacher's library. When false, the row just opens the document.
class FilesScreen extends StatefulWidget {
  final bool sharing;

  const FilesScreen({super.key, this.sharing = false});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Restores the saved library from SQLite; the screen's loading state
      // covers the round-trip.
      unawaited(context.read<LibraryProvider>().load());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final visible = library.visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppSearchField(
                hint: 'Search files…',
                controller: _search,
                onChanged: library.setQuery,
              ),
            ),
            const SizedBox(width: 8),
            // Icon-only so it does not steal the width the search box needs on
            // a 320px phone, but still a full 48dp target.
            FilledButton(
              onPressed: _addFiles,
              style: FilledButton.styleFrom(
                minimumSize: const Size(52, 48),
                padding: EdgeInsets.zero,
              ),
              child: const Icon(Icons.add, size: 22),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _filters(context, library),
        const SizedBox(height: 12),
        // Cross-fade between loading / empty / list instead of a hard swap.
        Expanded(
          child: AnimatedSwitcher(
            duration: Motion.standard,
            child: _body(context, library, visible),
          ),
        ),
      ],
    );
  }

  Future<void> _addFiles() async {
    final messenger = ScaffoldMessenger.of(context);
    final library = context.read<LibraryProvider>();
    final ok = await library.pickAndAdd();
    if (!mounted) return;
    if (!ok && library.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(library.error!)));
    }
  }

  Widget _filters(BuildContext context, LibraryProvider library) {
    final options = <(String, DocKind?)>[
      ('All', null),
      ('PDF', DocKind.pdf),
      ('Slides', DocKind.powerpoint),
      ('Docs', DocKind.word),
      ('Sheets', DocKind.excel),
      ('Images', DocKind.image),
      ('Text', DocKind.text),
      ('Video', DocKind.video),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (label, kind) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label),
                selected: library.filter == kind,
                onSelected: (_) => library.setFilter(kind),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, LibraryProvider library,
      List<SharedDocument> visible) {
    if (!library.isLoaded) {
      return const LoadingState(message: 'Loading files…');
    }
    if (library.error != null && visible.isEmpty) {
      return ErrorState(
        title: 'Could not load files',
        message: library.error!,
        onRetry: () => context.read<LibraryProvider>().load(),
      );
    }
    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.folder_outlined,
        title: library.query.isNotEmpty || library.filter != null
            ? 'No matching files'
            : 'No documents yet',
        subtitle: library.query.isNotEmpty || library.filter != null
            ? 'Try a different search or filter.'
            : 'PDF, PowerPoint, Word, Excel, images and text all open '
                'straight on this phone.',
        actionLabel: 'Add files',
        onAction: () => library.pickAndAdd(),
      );
    }
    if (context.isDesktop) {
      return GridView.builder(
        gridDelegate: docGridDelegate(mainExtent: 132),
        itemCount: visible.length,
        itemBuilder: (_, i) => _card(context, visible[i]),
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _card(context, visible[i]),
      ),
    );
  }

  Widget _card(BuildContext context, SharedDocument doc) {
    final library = context.read<LibraryProvider>();
    final sharing = widget.sharing;
    final running = sharing && context.watch<SessionProvider>().active != null;
    return DocumentCard(
      doc: doc,
      selected: context.watch<LibraryProvider>().selected?.id == doc.id,
      onTap: () {
        library.select(doc);
        // In the teacher's library the row is the main path: preview, share,
        // unshare. Anywhere else it just opens the file — there is no class
        // to share it to.
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => sharing
                ? ShareDocumentScreen(doc: doc)
                : DocumentScreen(doc: doc),
          ),
        );
      },
      onOpen: () {
        library.select(doc);
        // Used to only select the file. A button labelled "Open" has to open.
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DocumentScreen(doc: doc)),
        );
      },
      // One tap from the library to the board, without the share screen in
      // between. Mid-lesson that is the difference between two taps and four.
      onCast: sharing ? () => _cast(context, doc) : null,
      castBlockedReason: !sharing
          ? null
          : running
              ? null
              : 'No active session — create or start one first',
      onRemove: () => _confirmRemove(context, doc),
    );
  }

  /// Sends [doc] to the running session and opens the board.
  Future<void> _cast(BuildContext context, SharedDocument doc) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    context.read<LibraryProvider>().select(doc);
    // The host can refuse — the file may have been cleared from the phone, or
    // the session may have ended. Saying nothing left the teacher believing
    // everyone had it. Same honesty as the share screen's button.
    final ok = await context.read<SessionProvider>().shareDocument(doc);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'The students could not be sent this file. Check that the session '
            'is still running and the file is still on this device.'),
      ));
      return;
    }
    nav.push(
      MaterialPageRoute(builder: (_) => const TeacherPresentationScreen()),
    );
  }

  /// Deleting drops the file out of the library and off the phone's record of
  /// it, in one tap, with no way back. It is the only irreversible thing in
  /// this screen, so it asks first and says what it removed afterwards —
  /// a dialog alone leaves a teacher wondering whether it worked.
  Future<void> _confirmRemove(BuildContext context, SharedDocument doc) async {
    final library = context.read<LibraryProvider>();
    final name = '${doc.name}.${doc.extension}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from library?'),
        content: Text('$name will be taken off this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    library.remove(doc.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed $name')),
    );
  }
}
