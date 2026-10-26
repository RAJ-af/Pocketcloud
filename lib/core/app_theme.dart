import 'package:flutter/material.dart';

class AppColors {
  static const ink = Color(0xFF0B0E12);
  static const background = Color(0xFF0B0E12);
  static const surface = Color(0xFF141920);
  static const raised = Color(0xFF1B232B);
  static const border = Color(0xFF29333D);
  static const muted = Color(0xFF9AA7B3);
  static const white = Color(0xFFF4F7F5);
  static const accent = Color(0xFFD9FF67);
  static const accentDark = Color(0xFFBFD940);
  static const aqua = Color(0xFF67E8D6);
  static const danger = Color(0xFFFF777D);
  static const warning = Color(0xFFFFCB70);
}

class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.ink,
      secondary: AppColors.aqua,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.6,
        height: 1.05,
      ),
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
        height: 1.13,
      ),
      headlineMedium: TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.45,
      ),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.muted),
      labelStyle: const TextStyle(color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(54),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.white,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.raised,
    ),
    dividerColor: AppColors.border,
  );
}
