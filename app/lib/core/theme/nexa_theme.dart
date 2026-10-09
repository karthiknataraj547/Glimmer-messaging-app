import 'package:flutter/material.dart';

/// Modern Minimalist Design Tokens for NEXA.
class NexaColors {
  // Obsidian Dark Theme Tokens (Primary Modern Minimalist Aesthetic)
  static const Color canvasDark = Color(0xFF090D16);        // Deep Obsidian Canvas
  static const Color surfaceDark = Color(0xFF111827);       // Frosted Glass Card
  static const Color elevatedDark = Color(0xFF1E293B);      // Pill / Input Elevated
  static const Color borderDark = Color(0xFF26334A);        // Subtle 1px Border
  static const Color borderSubtleDark = Color(0x1AFFFFFF);  // 10% Alpha White

  // Re-map Light tokens to Dark tokens so all screens stay unified and avoid white-on-white text
  static const Color canvasLight = canvasDark;
  static const Color surfaceLight = surfaceDark;
  static const Color elevatedLight = elevatedDark;
  static const Color borderLight = borderDark;
  static const Color borderStrongLight = borderDark;
  static const Color backgroundLight = canvasDark;

  // Active Defaults (Obsidian Dark Focus)
  static const Color canvas = canvasDark;
  static const Color surface = surfaceDark;
  static const Color elevated = elevatedDark;
  static const Color border = borderDark;

  // Accents & Signals
  static const Color primary = Color(0xFF0284C7);          // Ocean Cyan
  static const Color cyanAccent = Color(0xFF00E5FF);      // Electric Cyan Accent
  static const Color emeraldSecure = Color(0xFF10B981);   // Verified E2EE Green
  static const Color amberAttention = Color(0xFFF59E0B);  // Warning / Attention
  static const Color rubyDestructive = Color(0xFFEF4444); // Destructive / End Call
  static const Color error = rubyDestructive;
  static const Color amberWarning = amberAttention;

  // Typography Tokens (High-Contrast Clean Text)
  static const Color textPrimary = Color(0xFFF8FAFC);      // Crisp White
  static const Color textSecondary = Color(0xFF94A3B8);    // Muted Slate
  static const Color textMuted = Color(0xFF64748B);        // Deep Slate

  // Re-map Light Typography Tokens to Crisp High-Contrast White/Slate
  static const Color textPrimaryLight = textPrimary;
  static const Color textSecondaryLight = textSecondary;
  static const Color textMutedLight = textMuted;
}

class NexaTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NexaColors.canvasDark,
      primaryColor: NexaColors.cyanAccent,
      cardColor: NexaColors.surfaceDark,
      dividerColor: NexaColors.borderDark,
      colorScheme: const ColorScheme.dark(
        primary: NexaColors.cyanAccent,
        secondary: NexaColors.emeraldSecure,
        surface: NexaColors.surfaceDark,
        error: NexaColors.rubyDestructive,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: NexaColors.textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: NexaColors.textPrimary, fontSize: 14),
        bodySmall: TextStyle(color: NexaColors.textSecondary, fontSize: 12),
        titleLarge: TextStyle(color: NexaColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: NexaColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(color: NexaColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
        labelLarge: TextStyle(color: NexaColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: NexaColors.textSecondary, fontSize: 12),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NexaColors.canvasDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: NexaColors.textPrimary),
        titleTextStyle: TextStyle(
          color: NexaColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NexaColors.surfaceDark,
        hintStyle: const TextStyle(color: NexaColors.textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: NexaColors.textSecondary, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NexaColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NexaColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NexaColors.cyanAccent, width: 1.5),
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
          side: const BorderSide(color: NexaColors.borderDark),
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

  static ThemeData get lightTheme => darkTheme;
}
