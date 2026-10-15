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
}
