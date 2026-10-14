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

  bool _syncPaused = false;
  bool get syncPaused => _syncPaused;

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

  void setSyncPaused(bool value) {
    _syncPaused = value;
    notifyListeners();
  }
}
