import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never leave a blank white screen: show a readable message instead.
  ErrorWidget.builder = (details) => const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'ClassCast hit a problem.\nPlease restart the app.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
  runApp(
    MultiProvider(
      providers: appProviders(),
      child: const ClassCastApp(),
    ),
  );
}
