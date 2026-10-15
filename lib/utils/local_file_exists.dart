import 'local_file.dart';

/// Whether a local file is still there.
///
/// Used by the library store: a picked file lives in the app's cache folder,
/// which Android may clear at any time, so a restored library entry can point
/// at a file that no longer exists. This asks the platform for existence only —
/// reading every library file end to end just to answer a yes/no question can
/// cost hundreds of megabytes at startup.
Future<bool> localFileExists(String path) => localFileExistsImpl(path);
