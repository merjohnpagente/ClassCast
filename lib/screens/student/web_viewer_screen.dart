import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/sync_provider.dart';
import '../../services/classcast_client.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/state_cards.dart';
import 'viewer_screen.dart';
import 'waiting_screen.dart';

/// Browser entry for students: the same viewer, optimized for
/// laptop/desktop widths, served from the teacher's local address
/// (e.g. `http://192.168.43.1:8080`). No internet-hosted site needed —
/// `flutter build web` output is hosted by the laptop server in `server/`.
class WebStudentViewer extends StatelessWidget {
  const WebStudentViewer({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final joined = sync.link == LinkState.live ||
        sync.link == LinkState.reconnecting;
    if (joined) sync.bind();
    final presenting =
        joined && sync.snapshot?.documentId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(sync.snapshot?.name ?? 'ClassCast Web Viewer'),
        actions: [
          if (sync.link == LinkState.live)
             Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: Text('Live',
                    style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          if (joined)
            TextButton.icon(
              onPressed: () => sync.leave(),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Leave'),
            ),
        ],
      ),
      body: ContentWidth(
        child: Padding(
          padding: EdgeInsets.all(context.pagePadding),
          child: !joined
              ? const EmptyState(
                  icon: Icons.language,
                  title: 'Open a classroom link',
                  subtitle:
                      'Use the teacher address, e.g. http://192.168.43.1:8080/s/CLASS-101',
                )
              : presenting
                  ? const StudentViewerScreen()
                  : StudentWaitingScreen(
                      onLeave: () => sync.leave()),
        ),
      ),
    );
  }
}
