import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import '../utils/local_ip.dart';

/// Local-network helpers for the offline classroom.
///
/// Never reports "Connected" until a real host answers:
/// use [probeHost] after joining Wi-Fi.
class NetworkService {
  final NetworkInfo _info = NetworkInfo();

  /// Actual device IP on the local network (e.g. `192.168.43.1`).
  ///
  /// Tries the Wi-Fi plugin first, then walks the interfaces. The fallback is
  /// not a nicety: when the phone is *serving* the network — a hotspot, which
  /// is how a teacher brings a room online — the plugin has no Wi-Fi
  /// association to report and answers null, so the QR code had no address in
  /// it and no student could ever join.
  Future<String> localIp() async {
    try {
      final ip = await _info.getWifiIP();
      // A hotspot or router hands out a private address. Anything else (a
      // carrier NAT address, a link-local one, or an emulator's 10.0.2.15)
      // cannot be typed into a QR code by a student, so it is rejected here
      // rather than advertised and failing for everyone.
      if (isPrivateAddress(ip)) return ip!;
    } catch (_) {
      // Fall through to the interface walk below.
    }
    try {
      final viaInterface = await localInterfaceIp();
      if (isPrivateAddress(viaInterface)) return viaInterface!;
    } catch (_) {
      // Nothing more to try.
    }
    return '';
  }

  /// True for addresses a student on the same network could actually reach:
  /// RFC1918 private ranges. Hotspot (192.168.43.x) and home/school Wi-Fi
  /// (192.168.0.x, 10.x, 172.16-31.x) are all covered.
  static bool isPrivateAddress(String? ip) {
    if (ip == null || ip.isEmpty) return false;
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
      octets.add(value);
    }
    if (octets[0] == 127 || octets[0] == 169 && octets[1] == 254) return false;
    if (octets[0] == 10) return true;
    if (octets[0] == 192 && octets[1] == 168) return true;
    if (octets[0] == 172 &&
        octets[1] >= 16 &&
        octets[1] <= 31) {
      return true;
    }
    return false;
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

  /// One tap check for the teacher: is the address in the QR code actually
  /// serving?
  ///
  /// This runs on the teacher's own device, so a connection to its own
  /// address short-circuits over the loopback route: it proves the host is
  /// up and answering, but it can never prove that students can reach it —
  /// whatever the Wi-Fi does to device-to-device traffic, this check answers
  /// the same. The success message says exactly that instead of implying a
  /// green result means the room is fine.
  static Future<({bool reachable, String? message})> checkHost({
    required String host,
    required int port,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (host.isEmpty || !isPrivateAddress(host)) {
      return (
        reachable: false,
        message: 'No local address yet. Turn on your hotspot, or connect to '
            'the classroom Wi-Fi.',
      );
    }
    try {
      final res = await http.get(Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/api/ping',
      )).timeout(timeout);
      if (res.statusCode == 200) {
        return (
          reachable: true,
          message: 'This phone answered at http://$host:$port. If students '
              'still cannot join, the Wi-Fi may be blocking device-to-device '
              'traffic — try a hotspot.',
        );
      }
      return (
        reachable: false,
        message: 'Port $port answered, but not ClassCast (code '
            '${res.statusCode}).',
      );
    } on TimeoutException {
      return (
        reachable: false,
        message: 'Nothing answered at $host:$port. Check the hotspot or '
            'Wi-Fi, and that this is the teacher phone.',
      );
    } catch (_) {
      return (
        reachable: false,
        message: 'Could not reach $host:$port. If students still cannot '
            'join, the network may be blocking device-to-device traffic.',
      );
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
      // `package:http` picks the right transport per platform (dart:io on
      // mobile, fetch/XHR on web), so this probe works in the browser too.
      final res = await http.get(Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/api/ping',
      )).timeout(timeout);
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}
