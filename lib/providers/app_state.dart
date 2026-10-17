import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/session_store.dart';
import 'library_provider.dart';
import 'session_provider.dart';

enum AppRole { none, teacher, student }

/// Puts this device into hosting mode.
///
/// Both ways in go through here: choosing Teacher on the role screen, and
/// starting a session from the student side. Anyone can host a classroom — a
/// student casting to the rest of the class is the same screen talking to the
/// same server, and the app has no accounts to tell one from the other — so
/// the role is where you begin, not what you are allowed to do.
void enterHostingMode(BuildContext context) {
  context.read<AppState>().setRole(AppRole.teacher);
  context.read<SessionProvider>().load();
  context.read<LibraryProvider>().load();
}

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
