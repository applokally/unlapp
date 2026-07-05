// VERSÃO: v30
import 'package:flutter/material.dart';

import 'unl_colors.dart';

class UnlTheme {
  const UnlTheme._();

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: UnlColors.background,
      colorScheme: const ColorScheme.dark(
        primary: UnlColors.gold,
        surface: UnlColors.background,
        onSurface: UnlColors.textPrimary,
        error: UnlColors.error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: UnlColors.background,
        foregroundColor: UnlColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: base.textTheme.copyWith(
        // Hierarquia principal suavizada para evitar títulos visualmente
        // excessivos, preservando leitura e destaque entre as seções.
        displayLarge: const TextStyle(
          color: UnlColors.textPrimary,
          fontSize: 38,
          height: 1.08,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.9,
        ),
        displayMedium: const TextStyle(
          color: UnlColors.textPrimary,
          fontSize: 31,
          height: 1.08,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.7,
        ),
        headlineLarge: const TextStyle(
          color: UnlColors.textPrimary,
          fontSize: 28,
          height: 1.08,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
        ),
        headlineMedium: const TextStyle(
          color: UnlColors.textPrimary,
          fontSize: 23,
          height: 1.16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        titleLarge: const TextStyle(
          color: UnlColors.textPrimary,
          fontSize: 19,
          height: 1.16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: const TextStyle(
          color: UnlColors.textStrong,
          fontSize: 16,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: const TextStyle(
          color: UnlColors.textSecondary,
          fontSize: 16,
          height: 1.6,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: const TextStyle(
          color: UnlColors.textSecondary,
          fontSize: 15,
          height: 1.55,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: const TextStyle(
          color: UnlColors.textMuted,
          fontSize: 13,
          height: 1.4,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: const TextStyle(
          color: UnlColors.gold,
          fontSize: 16,
          height: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: UnlColors.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 18,
        ),
        labelStyle: const TextStyle(
          color: UnlColors.textStrong,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: const TextStyle(
          color: UnlColors.textMuted,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        errorStyle: const TextStyle(
          color: UnlColors.error,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: UnlColors.borderStrong, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: UnlColors.goldBorder, width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: UnlColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: UnlColors.error, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: UnlColors.gold,
          foregroundColor: UnlColors.black,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}
