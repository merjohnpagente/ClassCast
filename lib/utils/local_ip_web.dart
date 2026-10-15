/// A browser has no network interfaces of its own to enumerate, and the
/// address a student should use depends on the host machine anyway.
///
/// This file is only compiled when `dart:io` is absent (see `local_ip.dart`).
Future<String?> localInterfaceIp() async => null;
