import 'package:flutter/material.dart';

/// Calm Orbit Design Tokens for NEXA.
class NexaColors {
  // Canvases & Surfaces
  static const Color canvas = Color(0xFF0A0D12);
  static const Color surface = Color(0xFF121721);
  static const Color elevated = Color(0xFF1B2232);
  static const Color border = Color(0xFF242D40);

  // Accents & Signals
  static const Color cyanAccent = Color(0xFF00E5FF);     // Primary focus glow
  static const Color emeraldSecure = Color(0xFF00E676);  // Verified E2E encryption
  static const Color amberAttention = Color(0xFFFFB300); // Reminders & pending actions
  static const Color rubyDestructive = Color(0xFFFF5252); // Critical alert / block

  // Typography Tokens
  static const Color textPrimary = Color(0xFFF0F4F8);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
}

class NexaTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NexaColors.canvas,
      primaryColor: NexaColors.cyanAccent,
      cardColor: NexaColors.surface,
      dividerColor: NexaColors.border,
      fontFamily: 'Inter',
      colorScheme: const ColorScheme.dark(
        primary: NexaColors.cyanAccent,
        secondary: NexaColors.emeraldSecure,
        surface: NexaColors.surface,
        error: NexaColors.rubyDestructive,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NexaColors.canvas,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: NexaColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NexaColors.cyanAccent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
