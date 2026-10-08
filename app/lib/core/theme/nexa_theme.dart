import 'package:flutter/material.dart';

/// Modern Minimalist Design Tokens for NEXA.
class NexaColors {
  // Obsidian Dark Theme Tokens (Primary Modern Aesthetic)
  static const Color canvasDark = Color(0xFF090D16);        // Deep Obsidian Canvas
  static const Color surfaceDark = Color(0xFF111827);       // Frosted Glass Card
  static const Color elevatedDark = Color(0xFF1E293B);      // Pill / Input Elevated
  static const Color borderDark = Color(0xFF26334A);        // Subtle 1px Border
  static const Color borderSubtleDark = Color(0x1AFFFFFF);  // 10% Alpha White

  // Light Theme Tokens (Minimalist Clean Slate)
  static const Color canvasLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color elevatedLight = Color(0xFFF1F5F9);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderStrongLight = Color(0xFFCBD5E1);

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
  static const Color backgroundLight = canvasLight;

  // Typography Tokens
  static const Color textPrimary = Color(0xFFF8FAFC);      // Crisp White
  static const Color textSecondary = Color(0xFF94A3B8);    // Muted Slate
  static const Color textMuted = Color(0xFF64748B);        // Deep Slate

  // Typography Tokens - Light
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF475569);
  static const Color textMutedLight = Color(0xFF94A3B8);
}

class NexaTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NexaColors.canvasDark,
      primaryColor: NexaColors.cyanAccent,
      cardColor: NexaColors.surfaceDark,
      dividerColor: NexaColors.borderDark,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.dark(
        primary: NexaColors.cyanAccent,
        secondary: NexaColors.emeraldSecure,
        surface: NexaColors.surfaceDark,
        error: NexaColors.rubyDestructive,
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
        iconTheme: IconThemeData(color: NexaColors.textPrimaryLight),
        titleTextStyle: TextStyle(
          color: NexaColors.textPrimaryLight,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}
