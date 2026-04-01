import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/supabase/supabase_client.dart';

class UpdateChecker {
  /// Checks remote app_versions table. Shows dialog if update available.
  /// Call this once after home screen loads.
  static Future<void> check(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(info.buildNumber) ?? 0;

      final data = await supabase
          .from('app_versions')
          .select('version_name, version_code, apk_url, release_notes, is_force_update')
          .eq('is_active', true)
          .maybeSingle();

      if (data == null) return;

      final remoteCode = (data['version_code'] as num?)?.toInt() ?? 0;
      if (remoteCode <= localCode) return;

      if (!context.mounted) return;

      _showUpdateDialog(
        context,
        versionName: data['version_name'] as String? ?? '',
        apkUrl: data['apk_url'] as String? ?? '',
        releaseNotes: data['release_notes'] as String?,
        isForce: data['is_force_update'] as bool? ?? false,
      );
    } catch (_) {
      // Silently ignore — update check is non-critical
    }
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String versionName,
    required String apkUrl,
    required String? releaseNotes,
    required bool isForce,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (ctx) => _UpdateDialog(
        versionName: versionName,
        apkUrl: apkUrl,
        releaseNotes: releaseNotes,
        isForce: isForce,
      ),
    );
  }
}

class _UpdateDialog extends StatelessWidget {
  final String versionName;
  final String apkUrl;
  final String? releaseNotes;
  final bool isForce;

  const _UpdateDialog({
    required this.versionName,
    required this.apkUrl,
    required this.releaseNotes,
    required this.isForce,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !isForce,
      child: Dialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 80),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  color: AppColors.primary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                isForce ? 'Update Wajib' : 'Update Tersedia',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 6),

              Text(
                'Versi $versionName telah tersedia.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),

              // Release notes
              if (releaseNotes != null && releaseNotes!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Yang baru:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        releaseNotes!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (isForce) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF856404)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Aplikasi harus diperbarui untuk melanjutkan.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF856404)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Buttons
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final uri = Uri.parse(apkUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Update Sekarang',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (!isForce) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.surfaceContainerHigh),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Nanti Saja',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
