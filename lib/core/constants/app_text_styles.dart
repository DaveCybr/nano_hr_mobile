import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  static const TextStyle heading1 = TextStyle(
    fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary,
  );
  static const TextStyle heading2 = TextStyle(
    fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
  );
  static const TextStyle heading3 = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.textPrimary,
  );
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 13, fontWeight: FontWeight.normal, color: AppColors.textSecondary,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 11, fontWeight: FontWeight.normal, color: AppColors.textMuted,
  );
  static const TextStyle button = TextStyle(
    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
  );
}
