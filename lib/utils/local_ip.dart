/// This device's own address on the local network.
///
/// Separate file from [NetworkService] because enumerating interfaces is a
/// `dart:io` job: a browser has no interfaces to list, so it gets an empty
/// answer rather than a compile error.
export 'local_ip_web.dart' if (dart.library.io) 'local_ip_io.dart';
