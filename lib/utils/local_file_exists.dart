/// Whether a local file is still there.
///
/// Used by the library store: a picked file lives in the app's cache folder,
/// which Android may clear at any time, so a restored library entry can point
/// at a file that no longer exists.
Future<bool> localFileExists(String path) async {
  if (path.isEmpty) return false;
  try {
    final bytes = await localFileReadBytes(path);
    return bytes != null && bytes.isNotEmpty;
  } catch (_) {
    return false;
  }
}