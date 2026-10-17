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

  /// Every address this device could be reached on, most likely first.
  ///
  /// The hotspot and the classroom Wi-Fi used to produce different results
  /// because only one address was ever chosen, and the choice came from
  /// whichever answered first rather than from which network the students were
  /// on. A phone that is on the router *and* serving a hotspot has two
  /// addresses on two subnets that cannot see each other, so which one is
  /// correct depends entirely on the student — it is not a property of this
  /// phone that any amount of guessing can settle.
  ///
  /// So the tethering address leads (that is the network a hotspot client is
  /// on), the Wi-Fi station address comes next (that is the router), and the
  /// plugin's answer is the last resort rather than the first choice: on a
  /// phone serving a hotspot it reports the station address, which is exactly
  /// the one a hotspot client cannot use.
  Future<List<String>> localAddressCandidates() async {
    final found = await localInterfaceAddresses();
    String? plugin;
    try {
      plugin = await _info.getWifiIP();
    } catch (_) {
      // No association reported — the hotspot case. The interfaces have it.
    }
    return rankAddresses(found, pluginIp: plugin);
  }

  /// Orders raw interface findings into the list of addresses to offer.
  ///
  /// Split out from [localAddressCandidates] because the ordering is the part
  /// worth pinning down: enumerating interfaces is whatever the device happens
  /// to have, so a test cannot rely on it — but the ranking can be tested.
  static List<String> rankAddresses(
    List<({String nic, String ip})> found, {
    String? pluginIp,
  }) {
    final ranked = <({int rank, String ip})>[];
    for (final entry in found) {
      if (!isPrivateAddress(entry.ip)) continue;
      final name = entry.nic.toLowerCase();
      if (name.startsWith('tun')) continue;
      ranked.add((rank: _rankFor(name), ip: entry.ip));
    }
    if (isPrivateAddress(pluginIp)) {
      // Last: the plugin only knows the station interface.
      ranked.add((rank: 3, ip: pluginIp!));
    }
    ranked.sort((a, b) => a.rank.compareTo(b.rank));
    final seen = <String>{};
    return [for (final entry in ranked) if (seen.add(entry.ip)) entry.ip];
  }

  static int _rankFor(String nic) {
    if (nic.startsWith('ap')) return 0;
    if (nic.startsWith('wlan')) return 1;
    return 2;
  }

  /// This device's own address on the local network (e.g. `192.168.43.1`).
  ///
  /// Just the best candidate: the first of [localAddressCandidates], which
  /// prefers the hotspot's own interface over the Wi-Fi address the plugin
  /// reports. Reporting that plugin address first is what made the hotspot and
  /// the classroom Wi-Fi behave differently from each other on the same phone.
  Future<String> localIp() async {
    final candidates = await localAddressCandidates();
    return candidates.isEmpty ? '' : candidates.first;
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
  ///
  /// [altHosts] are the teacher's other addresses — the hotspot one and the
  /// Wi-Fi one, whichever is not [host]. They travel with the code so a student
  /// on either network finds the classroom without the teacher having to
  /// re-print a different QR after switching networks mid-lesson. The
  /// student's phone tries them in order and keeps the one that answers.
  static String qrPayload({
    required String host,
    required int port,
    required String sessionId,
    List<String> altHosts = const [],
  }) {
    final alts = <String>[
      for (final alt in altHosts)
        if (alt.trim().isNotEmpty && alt.trim() != host.trim()) alt.trim(),
    ];
    final buffer = StringBuffer(
        'classcast://join?host=$host&port=$port&session=$sessionId');
    if (alts.isNotEmpty) buffer.write('&alt=${alts.join(',')}');
    return buffer.toString();
  }

  /// Parse a scanned QR payload. Accepts the `classcast://` scheme,
  /// a plain `http://host:port/s/ID`, or a bare session ID.
  ///
  /// [alts] are the teacher's other addresses, when the code carried them.
  static ({String host, int port, String sessionId, List<String> alts})?
      parseJoinInput(String raw) {
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
        return (
          host: host,
          port: port,
          sessionId: session,
          alts: _altsFrom(uri, host),
        );
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
          sessionId: session,
          alts: _altsFrom(uri, uri.host),
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
          alts: const <String>[],
        );
      }
      // Bare session ID — host still needed from hotspot step.
      return (host: '', port: 8080, sessionId: t, alts: const <String>[]);
    } catch (_) {
      return null;
    }
  }

  /// The extra addresses a joining code carries, if any.
  static List<String> _altsFrom(Uri uri, String host) {
    final raw = uri.queryParameters['alt'] ?? uri.queryParameters['hosts'] ?? '';
    final out = <String>[];
    for (final part in raw.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty || trimmed == host) continue;
      if (!isPrivateAddress(trimmed)) continue;
      if (out.contains(trimmed)) continue;
      out.add(trimmed);
    }
    return out;
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

  /// The first of [hosts] the teacher actually answers on, or null.
  ///
  /// A teacher who is on the classroom Wi-Fi and serving a hotspot has both
  /// addresses, and a student on one of those networks cannot reach the other.
  /// Trying them in order is what makes "same Wi-Fi" and "hotspot" the same
  /// experience instead of a coin flip on which address the phone happened to
  /// report first.
  static Future<String?> firstReachableAddress(
    List<String> hosts, {
    required int port,
    Duration timeout = const Duration(seconds: 3),
    Duration alternateTimeout = const Duration(milliseconds: 1500),
  }) async {
    for (var i = 0; i < hosts.length; i++) {
      final host = hosts[i].trim();
      if (host.isEmpty) continue;
      final ok = await probeHost(
        host: host,
        port: port,
        // The first address is the likely one and gets the full wait; the
        // alternates are fallbacks, and a student staring at a spinner does
        // not need to wait the whole timeout on each of them.
        timeout: i == 0 ? timeout : alternateTimeout,
      );
      if (ok) return host;
    }
    return null;
  }
}
