import 'dart:io';

import 'package:args/args.dart';

import '../lib/classcast_server.dart';

/// Laptop-hosted ClassCast server entry.
///
/// Serves the Flutter web build, session APIs, shared files,
/// and the WebSocket sync channel — all on the local network.
///
/// ```sh
/// dart pub get
/// dart run bin/classcast_server.dart --port 8080 --dir ./shared --web ./web
/// ```
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080')
    ..addOption('dir',
        help: 'Directory with shared documents', defaultsTo: './shared')
    ..addOption('web',
        help: 'Flutter web build to serve (optional)', defaultsTo: '');
  final opts = parser.parse(args);
  final port = int.tryParse(opts['port'] as String) ?? 8080;
  final dir = Directory(opts['dir'] as String);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final webOpt = (opts['web'] as String).trim();
  final webDir = webOpt.isEmpty ? null : webOpt;

  final server =
      ClasscastServer(port: port, filesDir: dir.path, webDir: webDir);
  final http = await server.serve();

  // Print the real LAN IPs so the teacher can share them / make a QR.
  final ips = await NetworkInterface.list(
      includeLoopback: false, type: InternetAddressType.IPv4);
  stdout.writeln('ClassCast Offline server on port ${http.port}');
  for (final nic in ips) {
    for (final addr in nic.addresses) {
      stdout.writeln('  http://${addr.address}:${http.port}/');
    }
  }
  if (webDir != null) stdout.writeln('Serving web build from $webDir');
  stdout.writeln('Shared files from ${dir.path}');
  stdout.writeln('Office -> PDF: install LibreOffice and run:');
  stdout.writeln(
      '  soffice --headless --convert-to pdf <file> --outdir ${dir.path}');
}
