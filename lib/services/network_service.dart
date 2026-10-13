import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// Local-network helpers for the offline classroom.
///
/// Never reports "Connected" until a real host answers:
/// use [probeHost] after joining Wi-Fi.
class NetworkService {
  final NetworkInfo _info = NetworkInfo();

  /// Actual device IP on the local Wi-Fi (e.g. `192.168.43.1`).
  /// Returns '' when unavailable (mobile data off / Wi-Fi off / web).
  Future<String> localIp() async {
    try {
      final ip = await _info.getWifiIP();
      return ip ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String?> wifiName() async {
    try {
      return await _info.getWifiName();
    } catch (_) {
      return null;
    }
  }

  /// Local joining address students type or scan.
  static String joinAddress(String hostIp, int port, String sessionId) =>
      'http://$hostIp:$port/s/$sessionId';

  /// Payload encoded into the classroom QR code.
  /// Format: `classcast://join?host=<ip>&port=<port>&session=<id>`
  static String qrPayload({
    required String host,
    required int port,
    required String sessionId,
  }) =>
      'classcast://join?host=$host&port=$port&session=$sessionId';

  /// Parse a scanned QR payload. Accepts the `classcast://` scheme,
  /// a plain `http://host:port/s/ID`, or a bare session ID.
  static ({String host, int port, String sessionId})? parseJoinInput(
      String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    try {
      if (t.startsWith('classcast://')) {
        final uri = Uri.parse(t);
        final host = uri.queryParameters['host'] ?? '';
        final port =
            int.tryParse(uri.queryParameters['port'] ?? '') ?? 8080;
        final session = uri.queryParameters['session'] ?? '';
        if (host.isEmpty || session.isEmpty) return null;
        return (host: host, port: port, sessionId: session);
      }
      if (t.startsWith('http://') || t.startsWith('https://')) {
        final uri = Uri.parse(t);
        final segments =
            uri.pathSegments.where((s) => s.isNotEmpty).toList();
        final session = segments.isEmpty ? '' : segments.last;
        if (uri.host.isEmpty || session.isEmpty) return null;
        return (
          host: uri.host,
          port: uri.hasPort ? uri.port : 8080,
          sessionId: session
        );
      }
      // Bare host / session forms.
      final hostMatch =
          RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d+))?(?:/s/(\S+))?$')
              .firstMatch(t);
      if (hostMatch != null) {
        return (
          host: hostMatch.group(1)!,
          port: int.tryParse(hostMatch.group(2) ?? '') ?? 8080,
          sessionId: hostMatch.group(3) ?? '',
        );
      }
      // Bare session ID — host still needed from hotspot step.
      return (host: '', port: 8080, sessionId: t);
    } catch (_) {
      return null;
    }
  }

  /// Returns true only when the teacher host answers an HTTP probe.
  /// Students call this before showing the "Connected" state.
  static Future<bool> probeHost({
    required String host,
    required int port,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (host.isEmpty) return false;
    try {
      final client = HttpClient()
        ..connectionTimeout = timeout;
      final req = await client
          .getUrl(Uri(scheme: 'http', host: host, port: port, path: '/api/ping'))
          .timeout(timeout);
      final res = await req.close().timeout(timeout);
      client.close(force: true);
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}
