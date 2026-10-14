/// Cross-platform access to a file path the teacher picked on device.
///
/// Android/iOS read the path with `dart:io`; the browser has no filesystem,
/// so the web implementation reports every path as unavailable and the UI
/// falls back to the URL served by the teacher host. Keeping both behind one
/// API is what lets `document_viewer.dart` compile for web.
export 'local_file_web.dart'
    if (dart.library.io) 'local_file_io.dart';