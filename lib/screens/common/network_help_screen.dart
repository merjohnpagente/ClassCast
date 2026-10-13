import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/status_bits.dart';

/// Icon-focused connection guide: hotspot -> QR/address -> join.
/// Shows honest states; never a false "Connected".
class NetworkHelpScreen extends StatelessWidget {
  final bool isTeacher;

  const NetworkHelpScreen({super.key, this.isTeacher = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect')),
      body: ContentWidth(
        maxWidth: 640,
        child: ListView(
          padding: EdgeInsets.all(context.pagePadding),
          children: [
            NetworkHelpBody(isTeacher: isTeacher),
          ],
        ),
      ),
    );
  }
}

/// Body-only version for embedding in tabs (no Scaffold of its own).
class NetworkHelpBody extends StatelessWidget {
  final bool isTeacher;

  const NetworkHelpBody({super.key, this.isTeacher = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isTeacher
              ? 'Ask students to follow these 3 steps.'
              : 'Follow these 3 steps to join.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.muted,
          ),
        ),
        const SizedBox(height: 8),
        StepTile(
          step: 1,
          icon: Icons.wifi,
          title: isTeacher
              ? 'Share your hotspot or Wi-Fi'
              : 'Join the teacher Wi-Fi or hotspot',
          subtitle: isTeacher
              ? 'Turn on your hotspot (or use the classroom Wi-Fi) and keep this app open.'
              : 'Open Wi-Fi settings and connect to the teacher hotspot or the same local Wi-Fi. No mobile data needed.',
        ),
        StepTile(
          step: 2,
          icon: Icons.qr_code_2,
          title: 'Scan the QR or enter the address',
          subtitle: isTeacher
              ? 'Show your session QR from the dashboard.'
              : 'Tap “Scan QR Code” or type the local address and session ID from the teacher.',
        ),
        StepTile(
          step: 3,
          icon: Icons.play_circle_outline,
          title: 'Join and view',
          subtitle:
              'Wait for the teacher to share. Your screen follows the teacher page automatically.',
        ),
        const SectionHeader(title: 'Connection states'),
        const Card(
          child: Column(
            children: [
              _StateRow(
                  icon: Icons.wifi,
                  color: AppColors.success,
                  label: 'Connected',
                  hint: 'Shown only after the host answers.'),
              Divider(height: 1),
              _StateRow(
                  icon: Icons.hourglass_bottom,
                  color: AppColors.warning,
                  label: 'Waiting for connection',
                  hint: 'Teacher has not shared yet.'),
              Divider(height: 1),
              _StateRow(
                  icon: Icons.wifi_off,
                  color: AppColors.error,
                  label: 'No local network',
                  hint: 'Join Wi-Fi or hotspot first.'),
              Divider(height: 1),
              _StateRow(
                  icon: Icons.sync,
                  color: AppColors.warning,
                  label: 'Reconnecting',
                  hint: 'Retrying automatically.'),
              Divider(height: 1),
              _StateRow(
                  icon: Icons.error_outline,
                  color: AppColors.error,
                  label: 'Session unavailable',
                  hint: 'Wrong address, or session ended.'),
            ],
          ),
        ),
      ],
    );
  }
}

class _StateRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String hint;

  const _StateRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.muted,
          )),
    );
  }
}
