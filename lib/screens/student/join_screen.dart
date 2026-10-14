import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../providers/sync_provider.dart';
import '../../services/classcast_client.dart';
import '../../services/session_store.dart';
import '../../theme/app_colors.dart';
import '../../utils/validators.dart';

/// Student join: scan QR or enter session ID / address + name.
/// No accounts, no cloud auth.
class JoinScreen extends StatefulWidget {
  final VoidCallback onJoined;

  const JoinScreen({super.key, required this.onJoined});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _input = TextEditingController();
  bool _joining = false;
  final bool _allowAnonymous = true;

  @override
  void initState() {
    super.initState();
    SessionStore().loadStudentName().then((saved) {
      if (saved != null && mounted) _name.text = saved;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _joining = true);
    final sync = context.read<SyncProvider>();
    final ok = await sync.join(
      rawInput: _input.text,
      studentName: _name.text,
    );
    if (!mounted) return;
    setState(() => _joining = false);
    if (ok) {
      if (_name.text.trim().isNotEmpty) {
        SessionStore().saveStudentName(_name.text.trim());
      }
      widget.onJoined();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Joined classroom')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(sync.error ?? 'Could not join. Try again.')),
      );
    }
  }

  void _openScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _QrScanPage(
          onScanned: (value) {
            _input.text = value;
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sync = context.watch<SyncProvider>();
    final joining = _joining || sync.link == LinkState.connecting;

    return ListView(
      children: [
        Text('Join Classroom',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            )),
        Text('Scan the teacher QR or enter the details below.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.muted,
            )),
        const SizedBox(height: 12),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                validator: (v) => Validators.studentName(v,
                    allowAnonymous: _allowAnonymous),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Your name (optional)',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _input,
                validator: Validators.sessionId,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Session ID or address',
                  hintText: 'CLASS-101 or 192.168.43.1:8080',
                  prefixIcon: Icon(Icons.tag_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: joining ? null : _join,
                child: joining
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white),
                      )
                    : const Text('Join Classroom'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12),
                    child: Text('or',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(
                                color: AppColors.muted)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openScanner,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR Code'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.wifi,
                    color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'First connect to the teacher hotspot or classroom Wi-Fi. '
                    'No mobile data or internet needed.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Minimal QR scanner page with manual-entry fallback.
class _QrScanPage extends StatefulWidget {
  final ValueChanged<String> onScanned;

  const _QrScanPage({required this.onScanned});

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  late final MobileScannerController _ctrl;
  bool _done = false;

  /// Stream state so we can show a real error (e.g. camera denied)
  /// instead of a silent black screen.
  StreamSubscription<Object>? _states;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
    _states = _ctrl.start().catchError((Object e) => _error = e);
  }

  @override
  void dispose() {
    _states?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: Column(
        children: [
          Expanded(child: _view()),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Point the camera at the teacher QR code.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _view() {
    return MobileScanner(
      controller: _ctrl,
      errorBuilder: (context, error) {
        return _cameraError(error);
      },
      onDetect: (capture) {
        if (_done) return;
        if (capture.barcodes.isEmpty) return;
        final code = capture.barcodes.first.rawValue;
        if (code == null || code.isEmpty) return;
        _done = true;
        widget.onScanned(code);
      },
    );
  }

  /// Honest failure state: the camera may be blocked by permissions or
  /// unavailable on this device. Always offer manual entry as a fallback.
  Widget _cameraError(Object error) {
    final denied = error is MobileScannerException &&
        (error.errorCode ==
                MobileScannerErrorCode.permissionDenied ||
            error.errorCode == MobileScannerErrorCode.unspecified);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              denied
                  ? Icons.no_photography_outlined
                  : Icons.videocam_off_outlined,
              size: 44,
              color: AppColors.muted,
            ),
            const SizedBox(height: 12),
            Text(
              denied
                  ? 'Camera permission is blocked'
                  : 'Camera unavailable',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              denied
                  ? 'Enable the camera permission for ClassCast in Android '
                      'Settings, then try again.'
                  : 'This device could not start the camera. '
                      'Ask the teacher for the session ID or address instead.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.keyboard, size: 18),
              label: const Text('Enter session ID instead'),
            ),
          ],
        ),
      ),
    );
  }
}
