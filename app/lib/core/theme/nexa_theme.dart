import 'package:flutter/material.dart';

/// Modern Minimalist Design Tokens for NEXA.
class NexaColors {
  // ==========================================================================
  // ADMIN PANEL DESIGN SYSTEM TOKENS (Obsidian Minimalist Control Deck)
  // ==========================================================================
  static const Color adminBgBase = Color(0xFF090B10);        // Deep Obsidian Background
  static const Color adminBgSurface = Color(0xFF10141D);     // Dark Control Surface
  static const Color adminBgElevated = Color(0xFF161C28);    // Elevated Element / Input
  static const Color adminBorderSubtle = Color(0x14FFFFFF);  // 1px Subtle Border (8% White)
  static const Color adminBorderHover = Color(0x29FFFFFF);   // 16% White Border
  static const Color adminBorderActive = Color(0x663B82F6);  // Active Focus Border
  
  static const Color adminAccentCyan = Color(0xFF38BDF8);    // Observability Cyan
  static const Color adminAccentBlue = Color(0xFF3B82F6);    // Telemetry Blue
  static const Color adminAccentEmerald = Color(0xFF10B981); // Verified Emerald
  static const Color adminAccentRose = Color(0xFFF43F5E);    // Destructive Rose
  static const Color adminAccentAmber = Color(0xFFF59E0B);   // Attention Amber
  static const Color adminAccentViolet = Color(0xFF8B5CF6);  // Key Violet

  static const Color adminTextMain = Color(0xFFF8FAFC);      // Crisp Text Primary
  static const Color adminTextMuted = Color(0xFF94A3B8);     // Telemetry Muted Text
  static const Color adminTextDim = Color(0xFF64748B);       // Monospace Subtitle Dim

  // Canonical App Surface Tokens
  static const Color canvasDark = adminBgBase;
  static const Color surfaceDark = adminBgSurface;
  static const Color elevatedDark = adminBgElevated;
  static const Color borderDark = adminBorderSubtle;
  static const Color borderSubtleDark = adminBorderSubtle;

  // Re-map Light tokens to Dark tokens for consistent dark mode
  static const Color canvasLight = canvasDark;
  static const Color surfaceLight = surfaceDark;
  static const Color elevatedLight = elevatedDark;
  static const Color borderLight = borderDark;
  static const Color borderStrongLight = adminBorderHover;
  static const Color backgroundLight = canvasDark;

  // Active Defaults
  static const Color canvas = canvasDark;
  static const Color surface = surfaceDark;
  static const Color elevated = elevatedDark;
  static const Color border = borderDark;

  // Accents & Signals
  static const Color primary = adminAccentBlue;
  static const Color cyanAccent = adminAccentCyan;
  static const Color emeraldSecure = adminAccentEmerald;
  static const Color amberAttention = adminAccentAmber;
  static const Color rubyDestructive = adminAccentRose;
  static const Color error = rubyDestructive;
  static const Color amberWarning = amberAttention;

  // Typography Tokens
  static const Color textPrimary = adminTextMain;
  static const Color textSecondary = adminTextMuted;
  static const Color textMuted = adminTextDim;

  static const Color textPrimaryLight = textPrimary;
  static const Color textSecondaryLight = textSecondary;
  static const Color textMutedLight = textMuted;

  // Subtle Sleek Admin Accents
  static const Color neonCyan = adminAccentCyan;
  static const Color neonEmerald = adminAccentEmerald;
  static const Color neonViolet = adminAccentViolet;
  static const Color neonPink = adminAccentRose;
  static const Color neonAmber = adminAccentAmber;
  static const Color cyberCardBg = adminBgSurface;

  static const LinearGradient cyberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
  );

  static const LinearGradient hologramGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
  );

  static const LinearGradient plasmaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF161C28), Color(0xFF10141D)],
  );

  static const LinearGradient bubbleOutgoingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E293B), Color(0xFF162032)],
  );

  static const LinearGradient cyberCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10141D), Color(0xFF10141D)],
  );

  static List<BoxShadow> get glowCyan => [
    BoxShadow(color: const Color(0xFF38BDF8).withValues(alpha: 0.12), blurRadius: 10, spreadRadius: 0),
  ];

  static List<BoxShadow> get glowEmerald => [
    BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.12), blurRadius: 10, spreadRadius: 0),
  ];

  static List<BoxShadow> get glowViolet => [
    BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.12), blurRadius: 10, spreadRadius: 0),
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
