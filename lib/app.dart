import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
            context.read<SessionProvider>().load(
                demoMode: app.demoMode);
            context.read<LibraryProvider>().load(
                demoMode: app.demoMode);
          },
          onStudent: () =>
              app.setRole(AppRole.student),
        ),
    };
  }
}

/// Provider wiring shared by Android, desktop, and web.
List<ChangeNotifierProvider> appProviders() {
  return [
    ChangeNotifierProvider(create: (_) => AppState()),
    ChangeNotifierProvider(create: (_) => SessionProvider()),
    ChangeNotifierProvider(create: (_) => LibraryProvider()),
    ChangeNotifierProvider(create: (_) => SyncProvider()),
  ];
}
