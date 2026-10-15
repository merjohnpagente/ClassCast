import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Never leave a blank white screen: show the real error so it can
  // be reported (screenshot this screen) and fixed.
  //
  // Debug only. In a release build this paints a raw exception — and a
  // "Copy error" button that puts a stack trace on the clipboard — onto a
  // projector screen in front of a class. Release builds get a plain,
  // say-nothing panel instead.
  ErrorWidget.builder = kDebugMode
      ? (details) => _errorPanel(details.exceptionAsString())
      : (details) => _errorPanel(null);

  runApp(
    MultiProvider(
      providers: appProviders(),
      child: const ClassCastApp(),
    ),
  );
}

Widget _errorPanel(String? message) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 40, color: Color(0xFFD64545)),
            const SizedBox(height: 12),
            const Text(
              'ClassCast hit a problem.',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (message != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8FC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message.length > 400 ? message.substring(0, 400) : message,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            const SizedBox(height: 12),
            if (message != null)
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: message));
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy error'),
              ),
          ],
        ),
      ),
    ),
  );
}
