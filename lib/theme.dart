import 'package:flutter/material.dart';

/// Paleta "Dark-First Utility" definida em docs/design_guidelines.json.
abstract final class AppColors {
  static const bg = Color(0xFF090D14);
  static const panel = Color(0xFF121A26);
  static const panel2 = Color(0xFF1B2738);
  static const text = Color(0xFFF1F5F9);
  static const muted = Color(0xFF94A3B8);
  static const line = Color(0xFF1E293B);
  static const amber = Color(0xFFF59E0B);
  static const green = Color(0xFF10B981);
  static const yellow = Color(0xFFFBBF24);
  static const red = Color(0xFFEF4444);
  static const blue = Color(0xFF3B82F6);
  static const cyan = Color(0xFF38BDF8);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.amber,
      onPrimary: AppColors.bg,
      surface: AppColors.panel,
      onSurface: AppColors.text,
      error: AppColors.red,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg, elevation: 0),
  );
}

abstract final class AppText {
  static const overline = TextStyle(color: AppColors.muted, fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700);
  static const kicker = TextStyle(color: AppColors.amber, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w800);
  static const h1 = TextStyle(color: AppColors.text, fontSize: 34, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -1);
  static const h2 = TextStyle(color: AppColors.text, fontSize: 26, fontWeight: FontWeight.w800);
  static const lead = TextStyle(color: AppColors.muted, fontSize: 15, height: 1.55);
  static const cardTitle = TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w800);
  static const body = TextStyle(color: AppColors.muted, fontSize: 13, height: 1.45);
  static const section = TextStyle(color: AppColors.muted, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w800);
}
