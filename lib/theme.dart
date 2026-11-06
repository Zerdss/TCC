import 'package:flutter/material.dart';

/// Paleta clara: fundo verde bem claro (quase branco), cartões brancos e
/// destaque em verde-floresta. Amarelo e vermelho ficam reservados para
/// ATENÇÃO e ALERTA, com tons escurecidos para ter contraste no fundo claro.
abstract final class AppColors {
  static const bg = Color(0xFFF1F8F3);
  static const panel = Color(0xFFFFFFFF);
  static const panel2 = Color(0xFFE3EFE6);
  static const text = Color(0xFF14261B);
  static const textSoft = Color(0xFF2E4436);
  static const muted = Color(0xFF5E7366);
  static const line = Color(0xFFD6E5DA);
  static const lineStrong = Color(0xFFB5CCBC);
  static const accent = Color(0xFF2E7D57);
  static const accentDark = Color(0xFF1F5E40);
  static const accentSoft = Color(0xFFD5EDDF);
  static const green = Color(0xFF15803D);
  static const yellow = Color(0xFFB7791F);
  static const orange = Color(0xFFD9822B);
  static const red = Color(0xFFDC2626);
  static const blue = Color(0xFF2563EB);
  static const cyan = Color(0xFF0E9AA7);
}

/// Fonte de títulos/números (condensada, "painel automotivo") e de texto.
const displayFont = 'BarlowCondensed';
const textFont = 'Manrope';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: textFont,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.accentDark,
      surface: AppColors.panel,
      onSurface: AppColors.text,
      error: AppColors.red,
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg, elevation: 0),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.panel),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.panel2),
      trackOutlineColor: WidgetStateProperty.all(AppColors.lineStrong),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.panel2,
      thumbColor: AppColors.accent,
      overlayColor: Color(0x332E7D57),
      valueIndicatorColor: AppColors.accent,
      valueIndicatorTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
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
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
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
      fontFamily: displayFont, color: AppColors.accent, fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w700);
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
