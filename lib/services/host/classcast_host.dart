/// The classroom host, from the teacher's own device.
///
/// Android and desktop run the real server (see `classcast_host_io.dart`); the
/// browser cannot listen on a socket, so it gets an honest no-op
/// (`classcast_host_web.dart`) instead of a compile error.
export 'classcast_host_web.dart'
    if (dart.library.io) 'classcast_host_io.dart';
