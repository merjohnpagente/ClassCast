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
class ClassCastApp extends StatefulWidget {
  const ClassCastApp({super.key});

  @override
  State<ClassCastApp> createState() => _ClassCastAppState();
}

class _ClassCastAppState extends State<ClassCastApp> {
  bool _splashed = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return MaterialApp(
      title: 'ClassCast Offline',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: responsiveTextScale,
      home: !_splashed
          ? SplashScreen(
              onFinished: () =>
                  setState(() => _splashed = true))
          : switch (app.role) {
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
            },
    );
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
