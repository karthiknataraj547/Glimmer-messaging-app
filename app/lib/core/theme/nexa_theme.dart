import 'package:flutter/material.dart';

/// Modern Minimalist Design Tokens for NEXA.
class NexaColors {
  // ==========================================================================
  // MAXIMALIST CYBERPUNK DESIGN SYSTEM TOKENS (Rich, Vibrant & User-Friendly)
  // ==========================================================================
  static const Color cyberBgVoid = Color(0xFF070913);        // Deep Cosmic Void
  static const Color cyberBgSurface = Color(0xFF0F1527);     // Cyber Glass Card Surface
  static const Color cyberBgElevated = Color(0xFF161F38);    // Elevated Interactive Surface
  static const Color cyberBorderSubtle = Color(0x3300F0FF);  // Glowing 20% Cyan Border
  static const Color cyberBorderGlow = Color(0x6600F0FF);    // 40% Glowing Cyan Border
  static const Color cyberBorderViolet = Color(0x408B5CF6);  // 25% Glowing Violet Border

  // Vibrant Neon Palette
  static const Color neonCyan = Color(0xFF00F0FF);          // Hyper Cyan
  static const Color neonViolet = Color(0xFF8B5CF6);        // Electric Violet
  static const Color neonEmerald = Color(0xFF00FFA3);       // Cyber Emerald
  static const Color neonPink = Color(0xFFEC4899);          // Laser Pink / Magenta
  static const Color neonAmber = Color(0xFFF59E0B);         // Radiant Amber
  static const Color neonBlue = Color(0xFF3B82F6);          // Electric Blue

  // Canonical App Surface Tokens
  static const Color canvasDark = cyberBgVoid;
  static const Color surfaceDark = cyberBgSurface;
  static const Color elevatedDark = cyberBgElevated;
  static const Color borderDark = cyberBorderSubtle;
  static const Color borderSubtleDark = cyberBorderSubtle;

  // Re-map Light tokens to Dark tokens for consistent dark mode
  static const Color canvasLight = canvasDark;
  static const Color surfaceLight = surfaceDark;
  static const Color elevatedLight = elevatedDark;
  static const Color borderLight = borderDark;
  static const Color borderStrongLight = cyberBorderGlow;
  static const Color backgroundLight = canvasDark;

  // Active Defaults
  static const Color canvas = canvasDark;
  static const Color surface = surfaceDark;
  static const Color elevated = elevatedDark;
  static const Color border = borderDark;

  // Accents & Signals
  static const Color primary = neonCyan;
  static const Color cyanAccent = neonCyan;
  static const Color emeraldSecure = neonEmerald;
  static const Color amberAttention = neonAmber;
  static const Color rubyDestructive = Color(0xFFF43F5E);
  static const Color error = rubyDestructive;
  static const Color amberWarning = amberAttention;

  // Typography Tokens (High Contrast & User Friendly)
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  static const Color cyberTextMain = Color(0xFFFFFFFF);
  static const Color cyberTextDim = Color(0xFF94A3B8);
  static const Color cyberTextMuted = Color(0xFF64748B);

  static const Color textPrimaryLight = textPrimary;
  static const Color textSecondaryLight = textSecondary;
  static const Color textMutedLight = textMuted;

  static const Color cyberCardBg = cyberBgSurface;

  // Maximalist Cyber Gradients
  static const LinearGradient cyberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00E5FF), Color(0xFF7C3AED)],
  );

  static const LinearGradient hologramGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00FFA3), Color(0xFF00E5FF)],
  );

  static const LinearGradient plasmaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
  );

  static const LinearGradient bubbleOutgoingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E1B4B), Color(0xFF0F3E5E)],
  );

  static const LinearGradient bubbleIncomingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF111728), Color(0xFF172038)],
  );

  static const LinearGradient cyberCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0F1527), Color(0xFF141C33)],
  );

  // High-Impact Ambient BoxShadow Glows
  static List<BoxShadow> get glowCyan => [
    BoxShadow(color: const Color(0xFF00F0FF).withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 0),
  ];

  static List<BoxShadow> get glowEmerald => [
    BoxShadow(color: const Color(0xFF00FFA3).withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 0),
  ];

  static List<BoxShadow> get glowViolet => [
    BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 0),
  ];
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
