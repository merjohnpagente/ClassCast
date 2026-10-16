import 'package:flutter/foundation.dart';

/// Whether a camera QR scanner exists on this platform.
///
/// `mobile_scanner` has no Windows implementation, and on desktop the camera is
/// not something a teacher can aim at a second screen anyway. This is asked
/// before the scanner is ever pushed, so a Windows build hides the row instead
/// of opening a page whose plugin throws `MissingPluginException` on the first
/// frame — which is exactly the kind of crash that looks like the app is
/// broken rather than that one button is unsupported.
///
/// The manual "Enter Session ID" field above it works everywhere, so nothing is
/// lost by the row being absent.
bool get qrScannerSupported {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Why the row is not there, for the tooltip and the explanation.
String get qrScannerUnsupportedReason => kIsWeb
    ? 'The camera is not available in a browser. Type the joining address '
        'instead.'
    : 'The camera is not available on a computer. Type the joining address '
        'instead.';
