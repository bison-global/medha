import 'package:flutter/material.dart';

/// Colours from the clickable prototype.
abstract final class MedhaColors {
  static const ink = Color(0xFF0E1320);
  static const inkDeep = Color(0xFF0B101B);
  static const surface = Color(0xFF161D2E);
  static const surfaceLow = Color(0xFF131A2A);
  static const bubble = Color(0xFF1A2236);
  static const line = Color(0xFF263049);
  static const lineSoft = Color(0xFF1F2840);
  static const text = Color(0xFFEEF1F7);
  static const textSoft = Color(0xFFC9CFDC);
  static const muted = Color(0xFFA9B2C6);
  static const faint = Color(0xFF8D97AD);
  static const accent = Color(0xFFF5A524);
  static const onAccent = Color(0xFF161208);
  static const success = Color(0xFF5FD0A5);
  static const danger = Color(0xFFE5564A);
}

ThemeData buildMedhaTheme() {
  final scheme = const ColorScheme.dark(
    primary: MedhaColors.accent,
    onPrimary: MedhaColors.onAccent,
    secondary: MedhaColors.success,
    surface: MedhaColors.ink,
    onSurface: MedhaColors.text,
    surfaceContainerHighest: MedhaColors.surface,
    surfaceContainerHigh: MedhaColors.surface,
    surfaceContainer: MedhaColors.surfaceLow,
    surfaceContainerLow: MedhaColors.surfaceLow,
    outline: MedhaColors.line,
    outlineVariant: MedhaColors.lineSoft,
    error: MedhaColors.danger,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

  return base.copyWith(
    scaffoldBackgroundColor: MedhaColors.ink,
    appBarTheme: const AppBarTheme(
      backgroundColor: MedhaColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    textTheme: base.textTheme.apply(bodyColor: MedhaColors.text, displayColor: MedhaColors.text),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: shape,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: shape,
        side: const BorderSide(color: MedhaColors.line, width: 1.5),
        foregroundColor: MedhaColors.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: MedhaColors.surfaceLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MedhaColors.surfaceLow,
      hintStyle: const TextStyle(color: MedhaColors.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: MedhaColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: MedhaColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: MedhaColors.accent)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: MedhaColors.text,
      contentTextStyle: TextStyle(color: MedhaColors.ink, fontSize: 14),
      actionTextColor: Color(0xFF8A4B00),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: MedhaColors.lineSoft, space: 1, thickness: 1),
  );
}
