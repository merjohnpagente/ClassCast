import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../providers/sync_provider.dart';
import '../../services/classcast_client.dart';
import '../../services/session_store.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/motion.dart';
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

  Future<void> _joinWith(String? rawInput) async {
    if (rawInput != null && rawInput.isNotEmpty) {
      _input.text = rawInput.trim();
    }
    await _join();
  }

  /// Opens the camera scanner. The scanner page pops *itself* with the payload,
  /// so the join screen stays underneath; scanning then joins straight away —
  /// pointing a phone at the teacher's QR is already the intent to join.
  Future<void> _openScanner() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const _QrScanPage(),
      ),
    );
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;
    await _joinWith(scanned);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sync = context.watch<SyncProvider>();
    final joining = _joining || sync.link == LinkState.connecting;

    return ContentWidth(
      maxWidth: 520,
      child: ListView(
      children: [
        FadeIn(
          child: Text('Join Classroom',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              )),
        ),
        FadeIn(
          delay: Motion.stagger(1),
          child: Text('Scan the teacher QR or enter the details below.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              )),
        ),
        const SizedBox(height: 16),
        // Scanning is the primary way into a classroom, so it comes first —
        // buried under a divider it looked like the fallback, not the main
        // action.
        FadeIn(
          delay: Motion.stagger(2),
          child: FilledButton.icon(
            onPressed: joining ? null : _openScanner,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan Teacher QR Code'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              textStyle: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or enter it manually',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 12),
        FadeIn(
          delay: Motion.stagger(3),
          child: Form(
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
              ],
            ),
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
      ),
    );
  }
}

/// Camera QR scanner, with an honest fallback when the camera cannot start.
///
/// The page returns the scanned payload through `Navigator.pop`, which is what
/// the join screen awaits — a scanner that popped its *parent* route left the
/// camera sitting on top of a dead join form.
class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  late final MobileScannerController _ctrl;
  bool _done = false;
  bool _torchOn = false;

  /// The back camera would not open even though the permission is granted, so
  /// the page switches to the front camera by itself once. A QR can be
  /// scanned with either lens; leaving the student on a black screen is not
  /// an option.
  bool _otherLensAttempted = false;
  bool _fallbackScheduled = false;
  bool _usingFrontCamera = false;

  @override
  void initState() {
    super.initState();
    _ctrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    // Release the camera immediately: leaving it running drains the battery
    // and keeps the camera indicator on after leaving the page.
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done || capture.barcodes.isEmpty) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.trim().isEmpty) continue;
      _done = true;
      Navigator.of(context).pop(value.trim());
      return;
    }
  }

  /// A clean restart: stop first, then start. Calling start() on a half-open
  /// camera only produces "already started" errors, which is why a plain retry
  /// never worked.
  Future<void> _restartCamera() async {
    try {
      await _ctrl.stop();
    } catch (_) {/* not running is fine */}
    try {
      await _ctrl.start();
    } catch (_) {/* the error panel stays and says why */}
  }

  /// Switches to the front camera once, automatically, when the back camera
  /// will not open for a reason other than a denied permission.
  void _tryOtherLens(MobileScannerException error) {
    if (_otherLensAttempted ||
        _done ||
        error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return;
    }
    // One attempt, ever: a second failure means the phone really has no
    // usable camera, and hammering start() only produces new errors.
    _otherLensAttempted = true;
    _usingFrontCamera = true;
    () async {
      try {
        await _ctrl.stop();
        await _ctrl.switchCamera();
        await _ctrl.start();
      } catch (_) {/* the error panel stays and says why */}
      if (mounted) setState(() {});
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            tooltip: _torchOn ? 'Turn off flashlight' : 'Flashlight',
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
            ),
            onPressed: () async {
              // `toggleTorch` throws when the camera never started (for
              // example the permission was denied), which must not crash the
              // page — the manual-entry button is the way out anyway.
              try {
                await _ctrl.toggleTorch();
                if (mounted) setState(() => _torchOn = !_torchOn);
              } catch (_) {/* torch is a convenience, not a requirement */}
            },
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _ctrl,
            fit: BoxFit.cover,
            onDetect: _onDetect,
            placeholderBuilder: (_, __) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorBuilder: (context, error, child) {
              // Scheduled exactly once: errorBuilder runs on every rebuild
              // while the camera is down, and every scheduling would otherwise
              // queue another camera restart.
              if (!_fallbackScheduled && !_done) {
                _fallbackScheduled = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _tryOtherLens(error);
                });
              }
              return _cameraError(error);
            },
            overlayBuilder: (context, constraints) => _scanOverlay(context),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _usingFrontCamera
                        ? 'Front camera — hold the phone facing the QR code.'
                        : 'Point the camera at the QR code on the teacher screen.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.keyboard),
                      label: const Text('Enter session ID instead'),
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

  /// Simple framing guide so the teacher knows where to hold the phone.
  Widget _scanOverlay(BuildContext context) {
    return Center(
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white70, width: 2),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  /// One short sentence for the actual reason, because "camera not working"
  /// with no next step is the most frustrating message in an app like this.
  String _cameraHint(bool denied) {
    // Browsers only expose the camera in a secure context: HTTPS, or
    // localhost. Opened from a phone over plain http://<teacher-ip>, it is not.
    final insecure = kIsWeb &&
        Uri.base.scheme != 'https' &&
        Uri.base.host != 'localhost';
    if (insecure) {
      return 'Browsers only allow the camera on a secure address. Open the app '
          'on your phone, or type the session ID below.';
    }
    return denied
        ? 'Allow the camera for ClassCast in your phone settings, then try '
            'again.'
        : 'Type the session ID instead — it is on the teacher screen.';
  }

  /// Machine-readable detail for the error panel. A report that only says
  /// "camera unavailable" cannot be fixed; a report that says
  /// "noCamera: No camera found or failed to open camera" can.
  static String _errorLine(MobileScannerException error) {
    final code = error.errorCode.name;
    final message = error.errorDetails?.message;
    final buffer = StringBuffer('Error: $code');
    if (message != null && message.trim().isNotEmpty) {
      buffer.write(' — ${message.trim()}');
    }
    return buffer.toString();
  }

  /// Honest failure state: the camera may be blocked by permissions or
  /// unavailable on this device. Always offer manual entry as a fallback.
  Widget _cameraError(MobileScannerException error) {
    final denied = error.errorCode ==
        MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
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
                color: Colors.white70,
              ),
              const SizedBox(height: 12),
              Text(
                denied ? 'Camera blocked' : 'Camera not available',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _cameraHint(denied),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 14, height: 1.45),
              ),
              // The technical detail, in small print: without the error code
              // every future "camera does not work" report is a dead end.
              const SizedBox(height: 10),
              Text(
                _errorLine(error),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 11, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // A camera that failed once often works after a clean
                  // stop-then-start: the student may have just granted the
                  // permission, or the other lens finished waking up.
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: _restartCamera,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Try again'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.keyboard, size: 18),
                    label: const Text('Enter session ID'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
