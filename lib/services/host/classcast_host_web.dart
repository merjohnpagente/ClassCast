/// Web stand-in for the in-app classroom host.
///
/// A browser tab cannot open a listening socket, so the teacher on the web
/// build still needs the laptop host (`server/`) to serve the session. Keeping
/// the same API means the rest of the app does not care which one it has.
class ClasscastHost {
  ClasscastHost._();

  static final ClasscastHost instance = ClasscastHost._();

  /// False here: the web build cannot host.
  bool get running => false;
  int get port => 0;
  String get advertisedIp => '';
  String get joinUrl => '';

  /// Presence policy lives on the io host; these exist so the API matches for
  /// the analyzer (which resolves this stub) and for any shared caller. The
  /// browser cannot host, so nothing here reads them.
  Duration presenceTimeout = const Duration(seconds: 30);
  Duration sweepInterval = const Duration(seconds: 10);

  /// Nothing is ever open here: this build cannot host.
  int get socketCount => 0;
  int get participantCount => 0;
  int get teacherSocketCount => 0;

  /// No web host exists, so the one reason it "failed" is fixed.
  String? get lastStartError =>
      'The browser cannot host a classroom. Use the app on a phone or laptop.';

  Future<bool> start({
    required int port,
    String advertisedIp = '',
  }) async =>
      false;

  Future<void> stop() async {}

  void registerDocument(String name, String path) {}

  void clearDocument() {}

  /// Nothing to point anywhere: this build does not host, and the analyzer
  /// resolves this stub rather than the real one.
  void setAdvertisedIp(String ip) {}
}
