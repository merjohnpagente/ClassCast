import 'dart:async';

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
import '../../widgets/ui_kit.dart';
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
    // A throw here used to surface as an unhandled async error on the join
    // screen. A missing saved name is not worth an error report.
    unawaited(SessionStore()
        .loadStudentName()
        .then((saved) {
          if (saved != null && mounted) _name.text = saved;
        })
        .catchError((_) {}));
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

    // The design's join screen: brand lockup, one field, one button, then the
    // scanner as the quiet alternative below it. Not a form with a camera
    // bolted on top.
    return ContentWidth(
      maxWidth: 440,
      child: ListView(
        padding: EdgeInsets.only(bottom: 24),
        children: [
          const SizedBox(height: 24),
          const Center(child: AppBrandLockup(logoSize: 64, gap: 14)),
          const SizedBox(height: 32),
          Text(
            'Join Classroom',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 20),
          const AppFieldLabel('Enter Session ID'),
          FadeIn(
            delay: Motion.stagger(1),
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
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Your name (optional)',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _input,
                    validator: Validators.sessionId,
                    textInputAction: TextInputAction.done,
                    // A session code is not prose: autocorrect would "helpfully"
                    // turn CLASS-101 into Class-l0l and the join would fail.
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      hintText: 'CLASS-101 or 192.168.43.1:8080',
                      prefixIcon: Icon(Icons.tag_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: joining ? null : _join,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                    child: joining
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('Join'),
                  ),
                ],
              ),
            ),
          ),
          const OrDivider(),
          // Scanning stays available, but as the alternative it is: a soft row
          // under the form instead of a filled button above it, so the screen
          // has one clear action instead of two competing ones.
          FadeIn(
            delay: Motion.stagger(2),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: AppListRow(
                icon: Icons.qr_code_scanner,
                title: 'Scan QR Code',
                subtitle: 'Use the camera to scan the teacher screen',
                trailing: const AppChevron(),
                onTap: joining ? null : _openScanner,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.wifi, size: 18, color: AppColors.muted),
              const SizedBox(width: 8),
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
          // Manual lens switch: some devices expose only one usable camera to
          // apps, and the automatic fallback should not be the only way out.
          IconButton(
            tooltip: _usingFrontCamera
                ? 'Use the back camera'
                : 'Use the front camera',
            icon: Icon(
              _usingFrontCamera
                  ? Icons.flip_camera_android_outlined
                  : Icons.camera_front_outlined,
              color: Colors.white,
            ),
            onPressed: () async {
              try {
                await _ctrl.stop();
                await _ctrl.switchCamera();
                await _ctrl.start();
                setState(() => _usingFrontCamera = !_usingFrontCamera);
              } catch (_) {/* the error panel says what happened */}
            },
          ),
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
            placeholderBuilder: (context) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorBuilder: (context, error) {
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
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _usingFrontCamera
                        ? 'Front camera — face the QR code.'
                        : 'Point the camera at the QR code.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                // The manual escape hatch is a safety net, not a second
                // action: a filled 48px button down here competed with the
                // viewfinder for attention on every single frame.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.keyboard, size: 18),
                    label: const Text('Enter session ID instead'),
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
  ///
  /// Corner brackets rather than a full box: the same target, drawn with a
  /// quarter of the ink, so the camera preview is what the eye lands on.
  Widget _scanOverlay(BuildContext context) {
    const size = 180.0;
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            for (final corner in _corners) Align(alignment: corner, child: _bracket(corner)),
          ],
        ),
      ),
    );
  }

  static const _corners = [
    Alignment.topLeft,
    Alignment.topRight,
    Alignment.bottomLeft,
    Alignment.bottomRight,
  ];

  Widget _bracket(Alignment alignment) {
    final isLeft = alignment.x < 0;
    final isTop = alignment.y < 0;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        border: Border(
          top: isTop
              ? const BorderSide(color: Colors.white, width: 2.5)
              : BorderSide.none,
          bottom: isTop
              ? BorderSide.none
              : const BorderSide(color: Colors.white, width: 2.5),
          left: isLeft
              ? const BorderSide(color: Colors.white, width: 2.5)
              : BorderSide.none,
          right: isLeft
              ? BorderSide.none
              : const BorderSide(color: Colors.white, width: 2.5),
        ),
        borderRadius: BorderRadius.only(
          topLeft: isTop && isLeft ? const Radius.circular(6) : Radius.zero,
          topRight: isTop && !isLeft ? const Radius.circular(6) : Radius.zero,
          bottomLeft:
              !isTop && isLeft ? const Radius.circular(6) : Radius.zero,
          bottomRight:
              !isTop && !isLeft ? const Radius.circular(6) : Radius.zero,
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
              // A Wrap, not a Row: "Try again" and "Enter session ID" together
              // need ~338px, and the camera-error panel only has 272px on a
              // 320px phone, so the row overflowed on the screen whose whole
              // job is telling a stuck student what to do next.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 8,
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
