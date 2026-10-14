import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/doc_types.dart';
import '../../models/shared_document.dart';
import '../../providers/library_provider.dart';
import '../../providers/session_provider.dart';
import '../../utils/responsive.dart';
import '../../widgets/document_card.dart';
import '../../widgets/motion.dart';
import '../../widgets/status_bits.dart';
import '../../widgets/state_cards.dart';
import '../teacher/share_document_screen.dart';

/// Reusable document management: recent, search, filters,
/// empty / loading / error states. Grid on desktop, list on phones.
/// When [sharing] is true (teacher), each file gets Share + Open actions.
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
      context.read<LibraryProvider>().load();
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
        FadeIn(
          child: SectionHeader(
            title: widget.sharing ? 'Documents' : 'Files',
            subtitle: library.items.isEmpty
                ? null
                : '${library.items.length} file'
                    '${library.items.length == 1 ? '' : 's'}',
          ),
        ),
        FadeIn(
          delay: Motion.stagger(1),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => library.setQuery(v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search files',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await library.pickAndAdd();
                  if (!mounted) return;
                  if (!ok && library.error != null) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(library.error!)),
                    );
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _filters(context, library),
        const SizedBox(height: 10),
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

  Widget _filters(BuildContext context, LibraryProvider library) {
    final options = <(String, DocKind?)>[
      ('All', null),
      ('PDF', DocKind.pdf),
      ('Slides', DocKind.powerpoint),
      ('Docs', DocKind.word),
      ('Sheets', DocKind.excel),
      ('Images', DocKind.image),
      ('Text', DocKind.text),
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
        child: _card(context, visible[i] as dynamic),
      ),
    );
  }

  Widget _card(BuildContext context, SharedDocument doc) {
    final sessions = context.read<SessionProvider>();
    final sharingToActive = widget.sharing && sessions.active != null;
    return DocumentCard(
      doc: doc,
      selected: context.watch<LibraryProvider>().selected?.id == doc.id,
      onTap: () {
        context.read<LibraryProvider>().select(doc);
        if (widget.sharing) {
          Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) =>
                    ShareDocumentScreen(doc: doc)),
          );
        }
      },
      onOpen: () =>
          context.read<LibraryProvider>().select(doc),
      onShare: sharingToActive
          ? () {
              sessions.shareDocument(doc);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Sharing ${doc.name}.${doc.extension}')),
              );
            }
          : null,
      onRemove: () =>
          context.read<LibraryProvider>().remove(doc.id),
    );
  }
}
