import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'providers/app_state.dart';
import 'providers/library_provider.dart';
import 'providers/session_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/role_selection_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/student/student_shell.dart';
import 'screens/teacher/teacher_shell.dart';
import 'theme/app_theme.dart';
import 'utils/responsive.dart';

/// ClassCast Offline root: splash -> role -> teacher / student shell.
///
/// NOTE: [ClassCastApp] itself never calls `context.watch` — the role
/// router ([_RootRouter]) sits below [MaterialApp], so its context is
/// always under the providers. This avoids the "Provider not found"
/// class of startup crashes.
class ClassCastApp extends StatelessWidget {
  const ClassCastApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClassCast Offline',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: responsiveTextScale,
      home: const _RootRouter(),
    );
  }
}

class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  bool _splashed = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (!_splashed) {
      return SplashScreen(
          onFinished: () => setState(() => _splashed = true));
    }
    return switch (app.role) {
      AppRole.teacher => const TeacherShell(),
      AppRole.student => const StudentShell(),
      AppRole.none => RoleSelectionScreen(
          onTeacher: () {
            app.setRole(AppRole.teacher);
            context.read<SessionProvider>().load();
            context.read<LibraryProvider>().load();
          },
          onStudent: () =>
              app.setRole(AppRole.student),
        ),
    };
  }
}

/// Provider wiring shared by Android, desktop, and web.
///
/// IMPORTANT: type arguments are explicit. If this list were typed as the
/// raw `List<ChangeNotifierProvider>` (= `ChangeNotifierProvider<dynamic>`),
/// Dart would infer every element as `<dynamic>` and register them as
/// `Provider<dynamic>`, so `context.watch<AppState>()` would throw
/// "Could not find the correct Provider<AppState>" at runtime.
List<SingleChildWidget> appProviders() {
  return [
    ChangeNotifierProvider<AppState>(create: (_) => AppState()),
    ChangeNotifierProvider<SessionProvider>(
        create: (_) => SessionProvider()),
    ChangeNotifierProvider<LibraryProvider>(
        create: (_) => LibraryProvider()),
    ChangeNotifierProvider<SyncProvider>(create: (_) => SyncProvider()),
  ];
}
