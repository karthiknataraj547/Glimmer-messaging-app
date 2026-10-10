import 'package:flutter/material.dart';

/// Light Themed Maximalism Design System for NEXA.
/// High contrast, vibrant multi-color gradients, snow-white cards, and joyful ergonomic UX.
class NexaColors {
  // ==========================================================================
  // LIGHT THEMED MAXIMALISM SURFACES & PALETTE
  // ==========================================================================
  static const Color lightBgCanvas = Color(0xFFF4F6FB);     // Radiant porcelain canvas
  static const Color lightBgSurface = Color(0xFFFFFFFF);    // Snow white card surface
  static const Color lightBgElevated = Color(0xFFF8FAFC);   // Soft pearl layer
  static const Color lightBgSubtle = Color(0xFFEEF2F6);     // Subtle pill/tag fill
  static const Color lightBorderSubtle = Color(0xFFE2E8F0); // Hairline slate border
  static const Color lightBorderGlow = Color(0x334F46E5);   // Radiant indigo accent border

  // Seamless alias mapping for all app components
  static const Color cyberBgVoid = lightBgCanvas;
  static const Color cyberBgSurface = lightBgSurface;
  static const Color cyberBgElevated = lightBgElevated;
  static const Color cyberBorderSubtle = lightBorderSubtle;
  static const Color cyberBorderGlow = lightBorderGlow;
  static const Color cyberBorderViolet = Color(0x267C3AED);

  // Vibrant Maximalist Accents (Optimized for maximum pop on light background)
  static const Color primary = Color(0xFF4F46E5);           // Electric Indigo
  static const Color electricIndigo = Color(0xFF4F46E5);    // Electric Indigo
  static const Color laserViolet = Color(0xFF7C3AED);       // Laser Violet
  static const Color mintEmerald = Color(0xFF059669);       // Mint Emerald
  static const Color coralPink = Color(0xFFE11D48);         // Hot Coral Pink
  static const Color radiantAmber = Color(0xFFD97706);      // Radiant Amber
  static const Color sunfireAmber = Color(0xFFD97706);      // Sunfire Amber
  static const Color vividAzure = Color(0xFF0284C7);        // Vivid Azure / Sky

  static const Color neonCyan = Color(0xFF0284C7);          // Vivid Azure / Sky
  static const Color neonViolet = Color(0xFF7C3AED);        // Laser Violet
  static const Color neonEmerald = Color(0xFF059669);       // Mint Emerald
  static const Color neonPink = Color(0xFFE11D48);          // Hot Coral Pink
  static const Color neonAmber = Color(0xFFD97706);         // Radiant Amber
  static const Color neonBlue = Color(0xFF2563EB);          // Electric Royal Blue

  static const Color cyanAccent = neonCyan;
  static const Color emeraldSecure = mintEmerald;
  static const Color amberAttention = radiantAmber;
  static const Color rubyDestructive = Color(0xFFE11D48);
  static const Color error = rubyDestructive;
  static const Color amberWarning = amberAttention;

  // Canonical App Surface Tokens
  static const Color canvasLight = lightBgCanvas;
  static const Color surfaceLight = lightBgSurface;
  static const Color elevatedLight = lightBgElevated;
  static const Color borderLight = lightBorderSubtle;
  static const Color borderStrongLight = Color(0xFFCBD5E1);
  static const Color backgroundLight = lightBgCanvas;

  static const Color canvasDark = canvasLight;
  static const Color surfaceDark = surfaceLight;
  static const Color elevatedDark = elevatedLight;
  static const Color borderDark = borderLight;
  static const Color borderSubtleDark = borderLight;

  static const Color canvas = canvasLight;
  static const Color surface = surfaceLight;
  static const Color elevated = elevatedLight;
  static const Color border = borderLight;

  // High-Contrast Light Theme Typography Tokens (Deep charcoal slate)
  static const Color textPrimary = Color(0xFF0F172A);       // 100% Crisp Legibility
  static const Color textSecondary = Color(0xFF475569);     // Medium Slate
  static const Color textMuted = Color(0xFF64748B);         // Cool Slate

  static const Color cyberTextMain = Color(0xFF0F172A);
  static const Color cyberTextDim = Color(0xFF475569);
  static const Color cyberTextMuted = Color(0xFF64748B);

  static const Color textPrimaryLight = textPrimary;
  static const Color textSecondaryLight = textSecondary;
  static const Color textMutedLight = textMuted;

  static const Color cyberCardBg = lightBgSurface;

  // Maximalist Light Gradients (Vibrant, Saturated, Joyful)
  static const LinearGradient cyberGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFEC4899)],
  );

  static const LinearGradient hologramGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), Color(0xFF0284C7)],
  );

  static const LinearGradient plasmaGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE11D48), Color(0xFFF97316)],
  );

  static const LinearGradient bubbleOutgoingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
  );

  static const LinearGradient bubbleIncomingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
  );

  static const LinearGradient cyberCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
  );

  // Soft Layered Colored Ambient Shadows for Light Theme
  static List<BoxShadow> get glowIndigo => [
    BoxShadow(color: const Color(0xFF4F46E5).withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
  ];

  static List<BoxShadow> get glowCyan => glowIndigo;

  static List<BoxShadow> get glowEmerald => [
    BoxShadow(color: const Color(0xFF059669).withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 4)),
  ];

  static List<BoxShadow> get glowViolet => [
    BoxShadow(color: const Color(0xFF7C3AED).withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
  ];

  static List<BoxShadow> get glowPink => [
    BoxShadow(color: const Color(0xFFE11D48).withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 4)),
  ];

  static List<BoxShadow> get cardShadow => [
    const BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3)),
    const BoxShadow(color: Color(0x064F46E5), blurRadius: 18, offset: Offset(0, 8)),
  ];
}

class NexaTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: NexaColors.canvasLight,
      primaryColor: NexaColors.primary,
      cardColor: NexaColors.surfaceLight,
      dividerColor: NexaColors.borderLight,
      colorScheme: const ColorScheme.light(
        primary: NexaColors.primary,
        secondary: NexaColors.neonViolet,
        surface: NexaColors.surfaceLight,
        error: NexaColors.rubyDestructive,
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: NexaColors.textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: NexaColors.textPrimary, fontSize: 14),
        bodySmall: TextStyle(color: NexaColors.textSecondary, fontSize: 12),
        titleLarge: TextStyle(color: NexaColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: NexaColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
        titleSmall: TextStyle(color: NexaColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
        labelLarge: TextStyle(color: NexaColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
        labelMedium: TextStyle(color: NexaColors.textSecondary, fontSize: 12),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NexaColors.surfaceLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: NexaColors.textPrimary),
        titleTextStyle: TextStyle(
          color: NexaColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NexaColors.surfaceLight,
        hintStyle: const TextStyle(color: NexaColors.textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: NexaColors.textSecondary, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: NexaColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: NexaColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: NexaColors.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NexaColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: const Color(0x334F46E5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NexaColors.primary,
          side: const BorderSide(color: NexaColors.borderLight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  static ThemeData get darkTheme => lightTheme;
}
