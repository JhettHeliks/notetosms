import 'package:flutter/material.dart';

class AppTheme {
  // Google Messages Material 3 Color Tokens
  static const Color seedColor = Color(0xFF1A73E8);

  static const Color surfaceContainerLowest = Color(0xFF0C0E12);
  static const Color surfaceContainerLow = Color(0xFF15181E);
  static const Color surfaceContainer = Color(0xFF1A1E26);
  static const Color surfaceContainerHigh = Color(0xFF242934);
  static const Color surfaceContainerHighest = Color(0xFF2F3543);

  static const Color primary = Color(0xFFA8C7FA);
  static const Color onPrimary = Color(0xFF062E6F);
  static const Color primaryContainer = Color(0xFF0842A0); // Google Messages Outgoing Bubble
  static const Color onPrimaryContainer = Color(0xFFD3E3FD);

  static const Color secondary = Color(0xFF7CDEF8);
  static const Color onSecondary = Color(0xFF003644);
  static const Color secondaryContainer = Color(0xFF283244);
  static const Color onSecondaryContainer = Color(0xFFD2E4FF);

  static const Color tertiary = Color(0xFF6DD58C);
  static const Color onTertiary = Color(0xFF00391A);
  static const Color tertiaryContainer = Color(0xFF0A532C);
  static const Color onTertiaryContainer = Color(0xFFC4EED0);

  static const Color accentAmber = Color(0xFFFFBA28);
  static const Color accentRose = Color(0xFFF2B8B5);

  static const Color textPrimary = Color(0xFFE2E2E6);
  static const Color textSecondary = Color(0xFFC4C6D0);
  static const Color textMuted = Color(0xFF8E9199);
  static const Color border = Color(0xFF44474E);

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    ).copyWith(
      surface: surfaceContainerLowest,
      surfaceContainerLowest: surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
      error: accentRose,
      outline: border,
      outlineVariant: surfaceContainerHigh,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: surfaceContainerLowest,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border, width: 0.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceContainerHighest,
        contentTextStyle: const TextStyle(color: textPrimary, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerHigh,
        hintStyle: const TextStyle(color: textMuted, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
    );
  }
}
