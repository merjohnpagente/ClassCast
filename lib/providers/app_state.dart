import 'package:flutter/foundation.dart';

import '../services/session_store.dart';

enum AppRole { none, teacher, student }

/// Global app state: role, server settings, sync preferences.
class AppState extends ChangeNotifier {
  final SessionStore _store = SessionStore();

  AppRole _role = AppRole.none;
  AppRole get role => _role;

  int _serverPort = 8080;
  int get serverPort => _serverPort;

  /// Pause state intentionally does NOT live here. It belongs to the active
  /// session (see `SessionProvider.setPaused`) because it has to reach
  /// students; keeping a second copy here meant the teacher's toggle was
  /// purely cosmetic.

  void setRole(AppRole role) {
    _role = role;
    _store.saveLastRole(role.name);
    notifyListeners();
  }

  void resetRole() {
    _role = AppRole.none;
    notifyListeners();
  }

  void setServerPort(int port) {
    _serverPort = port;
    notifyListeners();
  }
}
