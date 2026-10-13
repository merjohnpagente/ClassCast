/// Input validation for sessions and joining. No cloud auth required.
class Validators {
  static String? sessionName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter a session name';
    if (v.trim().length < 3) return 'At least 3 characters';
    if (v.trim().length > 60) return 'Keep it under 60 characters';
    return null;
  }

  static String? sessionId(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter a session ID or address';
    final t = v.trim();
    // Accept `CLASS-1A2B3C`, `192.168.43.1:8080`, or full `http://...`.
    if (t.contains('.') || t.contains(':') || t.startsWith('http')) {
      return null;
    }
    final code = t.replaceAll(' ', '').toUpperCase();
    if (!RegExp(r'^(CLASS-)?[A-Z0-9]{3,8}$').hasMatch(code)) {
      return 'Check the code, e.g. CLASS-101';
    }
    return null;
  }

  static String? studentName(String? v, {required bool allowAnonymous}) {
    if (allowAnonymous) return null;
    if (v == null || v.trim().isEmpty) return 'Enter your name';
    return null;
  }

  static String? port(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter a port';
    final p = int.tryParse(v.trim());
    if (p == null || p < 1024 || p > 65535) return 'Port 1024–65535';
    return null;
  }
}
