import 'package:flutter/material.dart';

/// One build's worth of colour tokens — light or dark.
///
/// The whole app reads its colours through [AppColors]'s names, and those names
/// resolve against whichever palette is active. Screens never see this class
/// directly; they only ever see the same tokens they always did, so making the
/// app dark did not mean touching three hundred call sites.
@immutable
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.onPrimary,
    required this.secondary,
    required this.secondarySoft,
    required this.background,
    required this.canvas,
    required this.surfaceSoft,
    required this.surface,
    required this.ink,
    required this.inkSecondary,
    required this.muted,
    required this.border,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.error,
    required this.errorBg,
    required this.info,
    required this.infoBg,
    required this.shadow,
    required this.pdf,
    required this.ppt,
    required this.word,
    required this.excel,
    required this.image,
    required this.text,
    required this.video,
  });

  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  /// Brand blue. In the dark palette it is a *light* tone with dark text on
  /// top — the Material 3 way round — because royal blue as a fill under white
  /// text reads as a muddy smudge once the page behind it is almost black.
  final Color primary;
  final Color primaryDark;
  final Color primarySoft;
  final Color onPrimary;
  final Color secondary;
  final Color secondarySoft;

  final Color background;
  final Color canvas;
  final Color surfaceSoft;
  final Color surface;

  final Color ink;
  final Color inkSecondary;
  final Color muted;
  final Color border;

  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color error;
  final Color errorBg;
  final Color info;
  final Color infoBg;

  final Color shadow;

  // File-type accents (always paired with an icon + label, never color alone).
  final Color pdf;
  final Color ppt;
  final Color word;
  final Color excel;
  final Color image;
  final Color text;
  final Color video;
}

/// The classroom daylight palette: white paper, navy ink, royal blue.
const lightPalette = AppPalette(
  brightness: Brightness.light,
  primary: Color(0xFF3568F5), // Royal blue
  primaryDark: Color(0xFF2549B8),
  primarySoft: Color(0xFFE6EDFF),
  onPrimary: Colors.white,
  secondary: Color(0xFF8B7CFF), // Soft lavender
  secondarySoft: Color(0xFFEFEBFF),
  background: Color(0xFFFFFFFF),
  canvas: Color(0xFFF6F8FC),
  surfaceSoft: Color(0xFFF6F8FC),
  surface: Colors.white,
  ink: Color(0xFF14213D), // dark navy
  inkSecondary: Color(0xFF3E4A63),
  muted: Color(0xFF6B7688), // muted gray (kept legible)
  border: Color(0xFFE4E9F2),
  // The semantic colours are read as text on their own tinted background —
  // a 12px "Live" label on successBg, an "Offline" on errorBg. The old values
  // were picked to look right as fills and measured 2.8:1, 3.3:1 and 3.8:1 on
  // those backgrounds, all failing WCAG AA by a wide margin. These measure
  // 4.9:1, 4.6:1 and 4.8:1, and 5.4 / 5.0 / 5.5 on plain white, so the same
  // token works as an icon, a border or a label.
  success: Color(0xFF0F7A3D),
  successBg: Color(0xFFE6F6EC),
  warning: Color(0xFF96650F),
  warningBg: Color(0xFFFFF3DF),
  error: Color(0xFFC03636),
  errorBg: Color(0xFFFFEBEB),
  info: Color(0xFF3568F5),
  infoBg: Color(0xFFE6EDFF),
  shadow: Color(0x0F14213D),
  pdf: Color(0xFFD64545),
  ppt: Color(0xFFE67E22),
  word: Color(0xFF3568F5),
  excel: Color(0xFF1F9D55),
  image: Color(0xFF8B7CFF),
  text: Color(0xFF7C879D),
  video: Color(0xFFB4417A),
);

/// The classroom after dark: near-black navy paper, light ink.
///
/// Not an inversion — an inversion of a document viewer would turn every
/// worksheet into a negative. It is the same design with the paper and the
/// ink swapped for their night values, and the semantic colours lightened
/// until they measure the same contrast ratios the light ones do (all
/// ≥ 4.5:1 against the surface they are read on).
const darkPalette = AppPalette(
  brightness: Brightness.dark,
  primary: Color(0xFF8FA9FF),
  primaryDark: Color(0xFFB9C7FF),
  primarySoft: Color(0xFF1F2B4F),
  onPrimary: Color(0xFF0B1020),
  secondary: Color(0xFFA79BFF),
  secondarySoft: Color(0xFF262245),
  background: Color(0xFF0E1320),
  canvas: Color(0xFF151B2B),
  surfaceSoft: Color(0xFF151B2B),
  surface: Color(0xFF1A2132),
  ink: Color(0xFFE9EDF7),
  inkSecondary: Color(0xFFC2CADC),
  muted: Color(0xFF98A2B8),
  border: Color(0xFF2A3346),
  success: Color(0xFF4CCB7A),
  successBg: Color(0xFF14301F),
  warning: Color(0xFFE3B25B),
  warningBg: Color(0xFF33270F),
  error: Color(0xFFF07F7F),
  errorBg: Color(0xFF3A1B1B),
  info: Color(0xFF8FA9FF),
  infoBg: Color(0xFF1F2B4F),
  shadow: Color(0x66000000),
  pdf: Color(0xFFE08585),
  ppt: Color(0xFFE8A45F),
  word: Color(0xFF8FA9FF),
  excel: Color(0xFF57C98A),
  image: Color(0xFFA79BFF),
  text: Color(0xFF98A2B8),
  video: Color(0xFFDD8CBE),
);

/// ClassCast Offline design tokens.
///
/// Minimal white + royal-blue system, 8pt spacing, Material 3 — and the same
/// system in its night values. The getters return whatever [active] holds; the
/// app root points [active] at the palette for the theme the teacher chose
/// before anything below it is built.
class AppColors {
  AppColors._();

  static AppPalette active = lightPalette;

  /// Points the whole app at a palette. Called from the root on every theme
  /// change, before the subtree that reads these tokens builds.
  static void apply(bool dark) =>
      active = dark ? darkPalette : lightPalette;

  static bool get isDark => active.brightness == Brightness.dark;

  static Color get primary => active.primary;
  static Color get primaryDark => active.primaryDark;
  static Color get primarySoft => active.primarySoft;
  static Color get onPrimary => active.onPrimary;
  static Color get secondary => active.secondary;
  static Color get secondarySoft => active.secondarySoft;

  static Color get background => active.background;
  static Color get canvas => active.canvas;
  static Color get surfaceSoft => active.surfaceSoft;
  static Color get surface => active.surface;

  static Color get ink => active.ink;
  static Color get inkSecondary => active.inkSecondary;
  static Color get muted => active.muted;
  static Color get border => active.border;

  static Color get success => active.success;
  static Color get successBg => active.successBg;
  static Color get warning => active.warning;
  static Color get warningBg => active.warningBg;
  static Color get error => active.error;
  static Color get errorBg => active.errorBg;
  static Color get info => active.info;
  static Color get infoBg => active.infoBg;

  static Color get shadow => active.shadow;

  static Color get pdf => active.pdf;
  static Color get ppt => active.ppt;
  static Color get word => active.word;
  static Color get excel => active.excel;
  static Color get image => active.image;
  static Color get text => active.text;
  static Color get video => active.video;
}

class AppRadius {
  static const double input = 12;
  static const double card = 16;
  static const double large = 20;
  static const double pill = 999;
}

/// 8-point spacing scale.
class AppSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;
}
