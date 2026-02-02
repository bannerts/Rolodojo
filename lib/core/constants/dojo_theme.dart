import 'package:flutter/material.dart';

/// Dojo Dark Theme - Visual Identity from ROLODOJO_UX_UI.md
class DojoColors {
  DojoColors._();

  /// Background: True black for OLED efficiency
  static const Color slate = Color(0xFF121212);

  /// Cards: Subtle elevation
  static const Color graphite = Color(0xFF1E1E1E);

  /// Accents: Used for AI insights and "Synthesis" highlights
  static const Color senseiGold = Color(0xFFFFD700);

  /// Status: Successful saves
  static const Color success = Color(0xFF4CAF50);

  /// Status: Security warnings
  static const Color alert = Color(0xFFF44336);

  /// Text: Primary
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Text: Secondary/Muted
  static const Color textSecondary = Color(0xFFB0B0B0);

  /// Text: Hint/Placeholder
  static const Color textHint = Color(0xFF707070);

  /// Border: Subtle dividers
  static const Color border = Color(0xFF2A2A2A);
}

/// Standard dimensions from the UI spec
class DojoDimens {
  DojoDimens._();

  /// Card corner radius
  static const double cardRadius = 16.0;

  /// Standard padding
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;

  /// Sensei Bar height
  static const double senseiBarHeight = 64.0;

  /// Icon sizes
  static const double iconSmall = 20.0;
  static const double iconMedium = 24.0;
  static const double iconLarge = 32.0;
}

/// Dojo Dark ThemeData for Flutter
class DojoTheme {
  DojoTheme._();

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DojoColors.slate,
      colorScheme: const ColorScheme.dark(
        surface: DojoColors.slate,
        primary: DojoColors.senseiGold,
        secondary: DojoColors.senseiGold,
        error: DojoColors.alert,
      ),
      cardTheme: CardTheme(
        color: DojoColors.graphite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DojoDimens.cardRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DojoColors.graphite,
        hintStyle: const TextStyle(color: DojoColors.textHint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DojoDimens.cardRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DojoDimens.cardRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DojoDimens.cardRadius),
          borderSide: const BorderSide(color: DojoColors.senseiGold, width: 1),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: DojoColors.textPrimary),
        bodyMedium: TextStyle(color: DojoColors.textPrimary),
        bodySmall: TextStyle(color: DojoColors.textSecondary),
        labelLarge: TextStyle(color: DojoColors.textPrimary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: DojoColors.slate,
        foregroundColor: DojoColors.textPrimary,
        elevation: 0,
      ),
    );
  }
}
