import 'dart:async';

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
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'utils/responsive.dart';

/// ClassCast Offline root: splash -> role -> teacher / student shell.
///
/// NOTE: [ClassCastApp] reads [AppState] for the theme only. It sits *under*
/// the providers created in `main`, so its context can see them; the role
/// router still lives below [MaterialApp] so its context is always under
/// them too.
class ClassCastApp extends StatelessWidget {
  const ClassCastApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<AppState>().themeMode;
    return MaterialApp(
      title: 'ClassCast Offline',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
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

class _RootRouterState extends State<_RootRouter> with WidgetsBindingObserver {
  bool _splashed = false;

  @override
  void initState() {
    super.initState();
    // A phone turning to dark while the app is open has to repaint: the app's
    // tokens are read through a static palette (see [AppColors]), so someone
    // has to notice, and this is the widget that points them.
    WidgetsBinding.instance.addObserver(this);
    // The stored choice is read once the app is up: the first frame draws in
    // the default, then this flips it if the other one was chosen.
    unawaited(context.read<AppState>().loadThemeMode());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Only matters while following the phone; a no-op otherwise.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    // Point the app's colour tokens at the palette the theme resolved to,
    // *before* anything below builds. Every screen reads AppColors, not
    // Theme.of, so without this the widgets that never touch the theme would
    // keep painting yesterday's white.
    AppColors.apply(Theme.of(context).brightness == Brightness.dark);

    if (!_splashed) {
      return SplashScreen(
          onFinished: () => setState(() => _splashed = true));
    }
    // Deliberately not `const`: when the palette flips, this rebuild has to
    // reach the shells, and a const child is the one thing a rebuild skips.
    return switch (app.role) {
      AppRole.teacher => TeacherShell(),
      AppRole.student => StudentShell(),
      AppRole.none => RoleSelectionScreen(
          onTeacher: () => enterHostingMode(context),
          onStudent: () => enterStudentMode(context),
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
