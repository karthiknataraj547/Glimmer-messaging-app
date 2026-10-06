import 'package:flutter/material.dart';

/// Modern Minimalist Design Tokens for NEXA.
class NexaColors {
  // Light Theme Tokens (Minimalist / Clean Slate)
  static const Color canvasLight = Color(0xFFF8FAFC);      // Ultra-clean canvas (slate-50)
  static const Color surfaceLight = Color(0xFFFFFFFF);     // Pure crisp surface
  static const Color elevatedLight = Color(0xFFF1F5F9);    // Pill/input background (slate-100)
  static const Color borderLight = Color(0xFFE2E8F0);      // Hairline subtle border (slate-200)
  static const Color borderStrongLight = Color(0xFFCBD5E1);// Defined border (slate-300)

  // Dark Theme Tokens (Deep Space)
  static const Color canvasDark = Color(0xFF0B0F17);
  static const Color surfaceDark = Color(0xFF131926);
  static const Color elevatedDark = Color(0xFF1C2436);
  static const Color borderDark = Color(0xFF263248);

  // Default references (Active light mode)
  static const Color canvas = canvasLight;
  static const Color surface = surfaceLight;
  static const Color elevated = elevatedLight;
  static const Color border = borderLight;

  // Accents & Signals
  static const Color primary = Color(0xFF0284C7);          // Ocean Cyan / Vibrant Sapphire
  static const Color cyanAccent = Color(0xFF0284C7);      // Primary focus
  static const Color emeraldSecure = Color(0xFF059669);   // Verified E2E encryption
  static const Color amberAttention = Color(0xFFD97706);  // Reminders & pending actions
  static const Color rubyDestructive = Color(0xFFE11D48); // Critical alert / block

  // Typography Tokens - Light
  static const Color textPrimary = Color(0xFF0F172A);      // Slate 900
  static const Color textSecondary = Color(0xFF475569);    // Slate 600
  static const Color textMuted = Color(0xFF94A3B8);        // Slate 400

  // Typography Tokens - Dark
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textMutedDark = Color(0xFF64748B);
}

class NexaTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: NexaColors.canvasLight,
      primaryColor: NexaColors.primary,
      cardColor: NexaColors.surfaceLight,
      dividerColor: NexaColors.borderLight,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.light(
        primary: NexaColors.primary,
        secondary: NexaColors.emeraldSecure,
        surface: NexaColors.surfaceLight,
        error: NexaColors.rubyDestructive,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NexaColors.surfaceLight,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        iconTheme: IconThemeData(color: NexaColors.textPrimary),
        titleTextStyle: TextStyle(
          color: NexaColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NexaColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NexaColors.textPrimary,
          side: const BorderSide(color: NexaColors.borderLight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NexaColors.canvasDark,
      primaryColor: const Color(0xFF38BDF8),
      cardColor: NexaColors.surfaceDark,
      dividerColor: NexaColors.borderDark,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF38BDF8),
        secondary: NexaColors.emeraldSecure,
        surface: NexaColors.surfaceDark,
        error: NexaColors.rubyDestructive,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NexaColors.canvasDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: NexaColors.textPrimaryDark,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
