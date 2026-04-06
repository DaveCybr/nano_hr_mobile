import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/supabase/supabase_client.dart';

class UpdateChecker {
  static Future<void> check(BuildContext context) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final localCode = int.tryParse(info.buildNumber) ?? 0;

      final data = await supabase
          .from('app_versions')
          .select('version_name, version_code, apk_url, release_notes, is_force_update')
          .eq('is_active', true)
          .maybeSingle();

      if (data == null) {
        debugPrint('[UpdateChecker] no active version found in app_versions');
        return;
      }

      final remoteCode = (data['version_code'] as num?)?.toInt() ?? 0;
      debugPrint('[UpdateChecker] localCode=$localCode remoteCode=$remoteCode');
      if (remoteCode <= localCode) return;

      if (!context.mounted) return;

      _showUpdateDialog(
        context,
        versionName: data['version_name'] as String? ?? '',
        apkUrl: data['apk_url'] as String? ?? '',
        releaseNotes: data['release_notes'] as String?,
        isForce: data['is_force_update'] as bool? ?? false,
      );
    } catch (e, st) {
      debugPrint('[UpdateChecker] error: $e\n$st');
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

class _UpdateDialog extends StatefulWidget {
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
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  bool _downloaded = false;
  double _progress = 0;
  String _statusText = '';
  String? _savePath;
  CancelToken? _cancelToken;

  /// Google Drive mengembalikan halaman konfirmasi virus scan untuk file besar.
  /// Tambahkan confirm=t dan ubah ke usercontent domain agar download langsung.
  String _resolveGoogleDriveUrl(String url) {
    if (!url.contains('drive.google.com') && !url.contains('drive.usercontent.google.com')) {
      return url;
    }

    // Ekstrak file ID dari berbagai format Google Drive URL
    String? fileId;

    // Format: /file/d/FILE_ID/
    final fileMatch = RegExp(r'/file/d/([a-zA-Z0-9_-]+)').firstMatch(url);
    if (fileMatch != null) fileId = fileMatch.group(1);

    // Format: ?id=FILE_ID atau &id=FILE_ID
    if (fileId == null) {
      final idMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(url);
      if (idMatch != null) fileId = idMatch.group(1);
    }

    if (fileId == null) return url;

    return 'https://drive.usercontent.google.com/download?id=$fileId&export=download&confirm=t';
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _statusText = 'Mempersiapkan download...';
    });

    try {
      final dir = await getExternalStorageDirectory();
      final savePath = '${dir!.path}/downloads/update.apk';

      final file = File(savePath);
      if (await file.exists()) await file.delete();
      await file.parent.create(recursive: true);

      _cancelToken = CancelToken();

      setState(() => _statusText = 'Menghubungi server...');
      final resolvedUrl = _resolveGoogleDriveUrl(widget.apkUrl);
      debugPrint('[UpdateChecker] resolved url: $resolvedUrl');

      await Dio().download(
        resolvedUrl,
        savePath,
        cancelToken: _cancelToken,
        options: Options(headers: {'User-Agent': 'Mozilla/5.0'}),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            setState(() {
              _progress = received / total;
              final mb = (received / 1024 / 1024).toStringAsFixed(1);
              final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
              _statusText = 'Mengunduh $mb / $totalMb MB';
            });
          }
        },
      );

      // Validasi file adalah APK (magic bytes: PK\x03\x04)
      final bytes = await file.openRead(0, 4).expand((b) => b).toList();
      if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
        await file.delete();
        throw Exception('File yang didownload bukan APK valid');
      }

      if (mounted) {
        setState(() {
          _downloading = false;
          _downloaded = true;
          _savePath = savePath;
        });
      }

      await _openInstaller();
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      debugPrint('[UpdateChecker] download error: $e');
      if (mounted) {
        setState(() {
          _downloading = false;
          _statusText = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mengunduh update. Coba lagi.')),
        );
      }
    }
  }

  Future<void> _openInstaller() async {
    if (_savePath == null) return;
    setState(() => _statusText = 'Membuka installer...');
    await OpenFilex.open(_savePath!);
    if (mounted) setState(() => _statusText = '');
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isForce && !_downloading,
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
                widget.isForce ? 'Update Wajib' : 'Update Tersedia',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 6),

              Text(
                'Versi ${widget.versionName} telah tersedia.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),

              // Release notes
              if (widget.releaseNotes != null && widget.releaseNotes!.isNotEmpty) ...[
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
                        widget.releaseNotes!,
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

              if (widget.isForce) ...[
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

              // Download progress
              if (_downloading) ...[
                Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 8,
                        backgroundColor: AppColors.surfaceContainerLow,
                        valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _statusText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (_progress > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${(_progress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ] else if (_downloaded) ...[
                // APK sudah didownload, tinggal install
                Column(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 32),
                    const SizedBox(height: 8),
                    const Text(
                      'Download selesai!',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    if (_statusText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(_statusText, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _openInstaller,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'Install Sekarang',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Buttons
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _downloadAndInstall,
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
                    if (!widget.isForce) ...[
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
            ],
          ),
        ),
      ),
    );
  }
}
