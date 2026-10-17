import 'package:meta/meta.dart' show visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart';

/// The version of the app that is actually installed.
///
/// Read from the build rather than typed into the settings screen: a hardcoded
/// number is right until the day a release is cut and nobody remembers to
/// change it, and "which build is this?" is the first question when someone
/// reports something not working.
class AppVersion {
  const AppVersion._();

  static String _version = '';
  static String _build = '';
  static bool _loaded = false;

  /// e.g. `1.2.6 (11)`. Empty until [load] has run.
  static String get label {
    if (!_loaded) return '';
    if (_build.isEmpty) return _version;
    return '$_version ($_build)';
  }

  static bool get isLoaded => _loaded;

  /// Reads it once. Never throws: on a platform that cannot answer, the row
  /// simply stays empty rather than taking the settings screen down with it.
  static Future<void> load() async {
    if (_loaded) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _build = info.buildNumber;
    } catch (_) {
      // No platform channel (a test, or an unusual build): no version to show.
    }
    _loaded = true;
  }

  /// For tests, which cannot reach the platform channel at all.
  @visibleForTesting
  static void overrideForTesting(String version, String build) {
    _version = version;
    _build = build;
    _loaded = true;
  }
}