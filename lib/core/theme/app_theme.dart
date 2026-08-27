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

  static ThemeData buildTheme(ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      scaffoldBackgroundColor: isDark ? colorScheme.surfaceContainerLowest : colorScheme.surface,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? colorScheme.surfaceContainerLowest : colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: isDark ? colorScheme.surfaceContainerLow : colorScheme.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5), width: 0.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: colorScheme.onSurface, fontSize: 13.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 15),
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
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

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

    return buildTheme(colorScheme);
  }

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return buildTheme(colorScheme);
  }
}
