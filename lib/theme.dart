import 'package:flutter/material.dart';

/// Paleta "Dark-First Utility" definida em docs/design_guidelines.json.
abstract final class AppColors {
  static const bg = Color(0xFF090D14);
  static const panel = Color(0xFF121A26);
  static const panel2 = Color(0xFF1B2738);
  static const text = Color(0xFFF1F5F9);
  static const textSoft = Color(0xFFCBD5E1);
  static const muted = Color(0xFF94A3B8);
  static const line = Color(0xFF1E293B);
  static const lineStrong = Color(0xFF334155);
  static const amber = Color(0xFFF59E0B);
  static const amberDark = Color(0xFFD97706);
  static const amberSoft = Color(0xFFFCD34D);
  static const green = Color(0xFF10B981);
  static const yellow = Color(0xFFFBBF24);
  static const red = Color(0xFFEF4444);
  static const blue = Color(0xFF3B82F6);
  static const cyan = Color(0xFF38BDF8);
}

/// Fonte de títulos/números (condensada, "painel automotivo") e de texto.
const displayFont = 'BarlowCondensed';
const textFont = 'Manrope';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: textFont,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.amber,
      onPrimary: AppColors.bg,
      secondary: AppColors.amberSoft,
      surface: AppColors.panel,
      onSurface: AppColors.text,
      error: AppColors.red,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg, elevation: 0),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.bg : AppColors.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.amber : AppColors.panel2),
      trackOutlineColor: WidgetStateProperty.all(AppColors.lineStrong),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.amber,
      inactiveTrackColor: AppColors.panel2,
      thumbColor: AppColors.amber,
      overlayColor: Color(0x33F59E0B),
      valueIndicatorColor: AppColors.amber,
      valueIndicatorTextStyle: TextStyle(color: AppColors.bg, fontWeight: FontWeight.w800),
      showValueIndicator: ShowValueIndicator.onDrag,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.panel2,
      contentTextStyle: TextStyle(color: AppColors.text, fontFamily: textFont),
      behavior: SnackBarBehavior.floating,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.lineStrong),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: textFont, fontWeight: FontWeight.w800),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.amber,
        foregroundColor: AppColors.bg,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: textFont, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

abstract final class AppText {
  static const overline = TextStyle(
      fontFamily: displayFont, color: AppColors.muted, fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.w600);
  static const brand = TextStyle(
      fontFamily: displayFont, color: AppColors.text, fontSize: 20, letterSpacing: 2, fontWeight: FontWeight.w800);
  static const kicker = TextStyle(
      fontFamily: displayFont, color: AppColors.amber, fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w700);
  static const h1 = TextStyle(
      fontFamily: displayFont, color: AppColors.text, fontSize: 46, height: 1.0, fontWeight: FontWeight.w800,
      letterSpacing: -0.5);
  static const h2 = TextStyle(
      fontFamily: displayFont, color: AppColors.text, fontSize: 34, height: 1.05, fontWeight: FontWeight.w800);
  static const h3 = TextStyle(
      fontFamily: displayFont, color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 0.5);
  static const number = TextStyle(fontFamily: displayFont, color: AppColors.text, fontWeight: FontWeight.w800);
  static const lead = TextStyle(color: AppColors.muted, fontSize: 15, height: 1.6);
  static const cardTitle = TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w800);
  static const body = TextStyle(color: AppColors.muted, fontSize: 13, height: 1.5);
  static const section = TextStyle(
      fontFamily: displayFont, color: AppColors.muted, fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w700);
}
