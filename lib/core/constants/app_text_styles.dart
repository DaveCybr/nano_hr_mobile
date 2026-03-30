import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  // ── Emerald Editorial Type Scale (Inter) ──────────────────────────────
  static const TextStyle displayLg = TextStyle(
    fontSize: 56, fontWeight: FontWeight.bold, color: AppColors.onSurface,
    height: 1.1,
  );
  static const TextStyle headlineLg = TextStyle(
    fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.onSurface,
    height: 1.2,
  );
  static const TextStyle titleMd = TextStyle(
    fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.onSurface,
    height: 1.3,
  );
  static const TextStyle bodyMd = TextStyle(
    fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.onSurface,
    height: 1.5,
  );
  static const TextStyle labelSm = TextStyle(
    fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted,
    letterSpacing: 0.05 * 11, height: 1.4,
  );

  // ── Legacy aliases ─────────────────────────────────────────────────────
  static const TextStyle heading1 = TextStyle(
    fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.onSurface,
  );
  static const TextStyle heading2 = TextStyle(
    fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.onSurface,
  );
  static const TextStyle heading3 = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.onSurface,
  );
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 13, fontWeight: FontWeight.normal, color: AppColors.textSecondary,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 11, fontWeight: FontWeight.normal, color: AppColors.textMuted,
  );
  static const TextStyle button = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onPrimary,
  );
}
