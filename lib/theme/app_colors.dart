import 'package:flutter/material.dart';

/// ClassCast Offline design tokens.
/// Minimal white + royal-blue system, 8pt spacing, Material 3.
class AppColors {
  static const primary = Color(0xFF3568F5); // Royal blue
  static const primaryDark = Color(0xFF2549B8);
  static const primarySoft = Color(0xFFE6EDFF);
  static const secondary = Color(0xFF8B7CFF); // Soft lavender
  static const secondarySoft = Color(0xFFEFEBFF);

  static const background = Color(0xFFFFFFFF);
  static const canvas = Color(0xFFF6F8FC); // very light gray
  static const surfaceSoft = Color(0xFFF6F8FC);
  static const surface = Colors.white;

  static const ink = Color(0xFF14213D); // dark navy
  static const inkSecondary = Color(0xFF3E4A63);
  static const muted = Color(0xFF7C879D); // muted gray
  static const border = Color(0xFFE4E9F2);

  static const success = Color(0xFF1F9D55);
  static const successBg = Color(0xFFE6F6EC);
  static const warning = Color(0xFFB7791F);
  static const warningBg = Color(0xFFFFF3DF);
  static const error = Color(0xFFD64545);
  static const errorBg = Color(0xFFFFEBEB);
  static const info = Color(0xFF3568F5);
  static const infoBg = Color(0xFFE6EDFF);

  // File-type accents (always paired with an icon + label, never color alone).
  static const pdf = Color(0xFFD64545);
  static const ppt = Color(0xFFE67E22);
  static const word = Color(0xFF3568F5);
  static const excel = Color(0xFF1F9D55);
  static const image = Color(0xFF8B7CFF);
  static const text = Color(0xFF7C879D);
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
