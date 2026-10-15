import 'dart:io';

/// This device's address, found by walking the network interfaces.
///
/// This exists because the Wi-Fi plugin answers nothing when the device is
/// *serving* the network rather than joining one — which is exactly the
/// hotspot case a teacher uses. A hotspot's address lives on `ap0`/`wlan0`,
/// and it is the one students have to be given.
Future<String?> localInterfaceIp() async {
  const virtualHints = <String>[
    'loopback', 'vmware', 'virtualbox', 'vethernet', 'hyper-v', 'docker',
    'wsl', 'tailscale', 'zerotier', 'bluetooth', 'vpn', 'ppp', 'rmnet',
  ];
  String? fallback;
  try {
    final interfaces = await NetworkInterface.list(includeLoopback: false);
    for (final nic in interfaces) {
      for (final addr in nic.addresses) {
        if (addr.isLoopback) continue;
        if (addr.type != InternetAddressType.IPv4) continue;
        final name = nic.name.toLowerCase();
        // Android hotspots live on wlan0 / ap0 — those are the good ones.
        final isHotspot = name.startsWith('wlan') || name.startsWith('ap');
        final isVirtual =
            virtualHints.any(name.contains) || name.startsWith('tun');
        if (isVirtual) continue;
        if (isHotspot) return addr.address;
        fallback ??= addr.address;
      }
    }
  } catch (_) {
    // Enumeration is best-effort: permissions or an unusual platform.
  }
  return fallback;
}
