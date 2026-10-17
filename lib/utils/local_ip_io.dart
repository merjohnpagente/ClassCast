import 'dart:io';

/// This device's addresses, from the network interfaces, best first.
///
/// This exists because the Wi-Fi plugin answers nothing when the device is
/// *serving* the network rather than joining one — which is exactly the
/// hotspot case a teacher uses. A hotspot's address lives on `ap0`/`wlan0`,
/// and it is the one students have to be given.
///
/// Order matters, and it is the reason the hotspot and the classroom Wi-Fi are
/// no longer two different behaviours. A phone that is on the school router
/// *and* serving a hotspot has two addresses on two subnets: `ap0` (or `wlan0`
/// in tether mode) is the one a student on the hotspot can reach, and the
/// station address is the one a student on the router can reach. Neither can
/// see the other, so both are reported and the caller offers both.
///
/// Only the pairing of interface name and address is returned: which of them a
/// student can actually use depends on the network they are on, and
/// `NetworkService` owns that judgement.
Future<List<({String nic, String ip})>> localInterfaceAddresses() async {
  const virtualHints = <String>[
    'loopback', 'vmware', 'virtualbox', 'vethernet', 'hyper-v', 'docker',
    'wsl', 'tailscale', 'zerotier', 'bluetooth', 'vpn', 'ppp', 'rmnet',
  ];
  final found = <({String nic, String ip, int rank})>[];
  try {
    final interfaces = await NetworkInterface.list(includeLoopback: false);
    for (final nic in interfaces) {
      final name = nic.name.toLowerCase();
      if (virtualHints.any(name.contains) || name.startsWith('tun')) continue;
      final rank = _nicRank(name);
      for (final addr in nic.addresses) {
        if (addr.isLoopback) continue;
        if (addr.type != InternetAddressType.IPv4) continue;
        found.add((nic: name, ip: addr.address, rank: rank));
      }
    }
  } catch (_) {
    // Enumeration is best-effort: permissions or an unusual platform.
  }
  found.sort((a, b) {
    // The address is a tiebreaker on purpose: the list is re-read while a
    // session is live, and an unstable order for two interfaces of the same
    // kind would have the app flip the advertised address back and forth.
    final rank = a.rank.compareTo(b.rank);
    return rank != 0 ? rank : a.ip.compareTo(b.ip);
  });
  return [
    for (final entry in found) (nic: entry.nic, ip: entry.ip),
  ];
}

/// `ap0` is Android's tethering interface and is *only* the network a hotspot
/// client is on, so it leads. `wlan0` carries the station address — the router
/// — and doubles as the tether address on some devices, which is why it is
/// second rather than excluded. Everything else is a last resort.
int _nicRank(String name) {
  if (name.startsWith('ap')) return 0;
  if (name.startsWith('wlan')) return 1;
  return 2;
}

/// This device's address, found by walking the network interfaces.
Future<String?> localInterfaceIp() async {
  final addresses = await localInterfaceAddresses();
  return addresses.isEmpty ? null : addresses.first.ip;
}
