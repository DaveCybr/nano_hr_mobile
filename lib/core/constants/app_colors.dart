import 'package:flutter/material.dart';

class AppColors {
  // ── Emerald Editorial Palette ──────────────────────────────────────────
  // Primary greens
  static const Color primary          = Color(0xFF006036); // Deep Forest
  static const Color primaryContainer = Color(0xFF1A7A4A); // Functional green
  static const Color secondary        = Color(0xFF006D37); // Living Green

  // Surfaces (light, mint-infused)
  static const Color surface              = Color(0xFFF8F9FD);
  static const Color surfaceContainerLow  = Color(0xFFEFF1F5);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerHigh = Color(0xFFE4E7EF);

  // Text (tinted neutrals — no pure black/grey)
  static const Color onSurface        = Color(0xFF191C1F); // primary ink
  static const Color textSecondary    = Color(0xFF3F4941); // green-tinted neutral
  static const Color textMuted        = Color(0xFF6B7280); // muted label

  // On-primary
  static const Color onPrimary        = Color(0xFFFFFFFF);

  // Status
  static const Color success          = Color(0xFF006D37); // secondary green
  static const Color warning          = Color(0xFFB45309);
  static const Color danger           = Color(0xFFB91C1C);
  static const Color errorContainer   = Color(0xFFFFDAD6);

  // Outline (ghost border — used at low opacity only)
  static const Color outlineVariant   = Color(0xFF3F4941); // use at 0.15 opacity

  // ── Legacy aliases (keep other screens compiling) ──────────────────────
  static const Color bgPrimary        = surface;
  static const Color bgSecondary      = surfaceContainerLow;
  static const Color bgCard           = surfaceContainerLowest;
  static const Color bgCardLight      = surfaceContainerLow;
  static const Color primaryDark      = primaryContainer;
  static const Color orange           = Color(0xFFD97706);
  static const Color border           = Color(0x263F4941); // outlineVariant @ 15%

  static const Color textPrimary      = onSurface;

  static const Color badgeHadir       = Color(0xFF006D37);
  static const Color badgeTerlambat   = Color(0xFFB45309);
  static const Color badgeTidakHadir  = Color(0xFFB91C1C);
  static const Color badgeCuti        = Color(0xFF6D28D9);
}
