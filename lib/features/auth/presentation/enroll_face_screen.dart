import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import '../providers/auth_provider.dart';

class EnrollFaceScreen extends ConsumerStatefulWidget {
  const EnrollFaceScreen({super.key});

  @override
  ConsumerState<EnrollFaceScreen> createState() => _EnrollFaceScreenState();
}

class _EnrollFaceScreenState extends ConsumerState<EnrollFaceScreen> {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraReady  = false;
  bool _processing   = false;
  String? _error;
  String _status     = 'Posisikan wajah Anda dalam bingkai';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      final front = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      _cameraController = CameraController(front, ResolutionPreset.high);
      await _cameraController!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal membuka kamera: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _captureAndEnroll() async {
    if (_cameraController == null || !_cameraReady || _processing) return;
    setState(() { _processing = true; _status = 'Memproses wajah...'; _error = null; });

    try {
      // 1. Ambil foto
      final photo = await _cameraController!.takePicture();
      final imageBytes = await File(photo.path).readAsBytes();
      final base64Image = base64Encode(imageBytes);

      setState(() => _status = 'Menghubungi Face++ ...');

      debugPrint('Step 1: Photo captured, size=${imageBytes.length}');

      // 2. Detect face via Face++
      final detectRes = await http.post(
        Uri.parse('${AppConstants.faceppBaseUrl}/detect'),
        body: {
          'api_key':        AppConstants.faceppApiKey,
          'api_secret':     AppConstants.faceppApiSecret,
          'image_base64':   base64Image,
          'return_attributes': 'none',
        },
      );

      final detectData = jsonDecode(detectRes.body) as Map<String, dynamic>;

      if (detectData['faces'] == null || (detectData['faces'] as List).isEmpty) {
        setState(() {
          _error = 'Wajah tidak terdeteksi. Pastikan pencahayaan cukup dan wajah terlihat jelas.';
          _status = 'Posisikan wajah Anda dalam bingkai';
          _processing = false;
        });
        return;
      }

      final faceToken = detectData['faces'][0]['face_token'] as String;
      debugPrint('Step 2: Face detected, token=$faceToken');
      setState(() => _status = 'Menyimpan data wajah...');

      // 3. Upload foto ke Supabase Storage
      final session = supabase.auth.currentSession!;
      final userId  = session.user.id;
      final fileName = 'face_$userId.jpg';
      debugPrint('Step 3: Uploading to storage, file=$fileName');

      await supabase.storage
          .from('employee-photos')
          .uploadBinary(
            fileName,
            imageBytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );

      final photoUrl = supabase.storage
          .from('employee-photos')
          .getPublicUrl(fileName);

      // 4. Simpan face_token ke tabel employees
      final repo = ref.read(authRepositoryProvider);
      await repo.saveFaceToken(
        faceToken: faceToken,
        facePhotoUrl: photoUrl,
      );

      if (!mounted) return;
      setState(() => _status = 'Berhasil! Mengarahkan ke beranda...');
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) context.go('/home');
    } catch (e, st) {
      debugPrint('=== ENROLL FACE ERROR ===');
      debugPrint('Error: $e');
      debugPrint('Stack: $st');
      setState(() {
        _error = 'Terjadi kesalahan: $e';
        _status = 'Posisikan wajah Anda dalam bingkai';
        _processing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('Daftarkan Wajah Anda', style: AppTextStyles.heading2),
                  SizedBox(height: 8),
                  Text(
                    'Foto wajah digunakan untuk verifikasi saat absensi. Lakukan sekali saja.',
                    style: AppTextStyles.bodySecondary,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // Camera preview
            Expanded(
              child: _error != null && !_cameraReady
                  ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.danger)))
                  : _cameraReady
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            CameraPreview(_cameraController!),

                            // Face frame overlay
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.7,
                              height: MediaQuery.of(context).size.width * 0.85,
                              child: CustomPaint(painter: _FaceFramePainter()),
                            ),

                            // Status text
                            Positioned(
                              bottom: 20,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(_status,
                                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                              ),
                            ),
                          ],
                        )
                      : const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        ),
            ),

            // Error message
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                      textAlign: TextAlign.center),
                ),
              ),

            // Capture button
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _processing ? null : _captureAndEnroll,
                    child: Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _processing ? AppColors.textMuted : AppColors.primary,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: _processing
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.face_retouching_natural,
                              color: Colors.white, size: 32),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Tap untuk ambil foto wajah', style: AppTextStyles.caption),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      supabase.auth.signOut().then((_) {
                        if (mounted) router.go('/login');
                      });
                    },
                    child: const Text('Keluar',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const radius = 12.0;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Top-left
    canvas.drawLine(Offset(rect.left + radius, rect.top),
        Offset(rect.left + cornerLength, rect.top), paint);
    canvas.drawLine(Offset(rect.left, rect.top + radius),
        Offset(rect.left, rect.top + cornerLength), paint);

    // Top-right
    canvas.drawLine(Offset(rect.right - cornerLength, rect.top),
        Offset(rect.right - radius, rect.top), paint);
    canvas.drawLine(Offset(rect.right, rect.top + radius),
        Offset(rect.right, rect.top + cornerLength), paint);

    // Bottom-left
    canvas.drawLine(Offset(rect.left + radius, rect.bottom),
        Offset(rect.left + cornerLength, rect.bottom), paint);
    canvas.drawLine(Offset(rect.left, rect.bottom - cornerLength),
        Offset(rect.left, rect.bottom - radius), paint);

    // Bottom-right
    canvas.drawLine(Offset(rect.right - cornerLength, rect.bottom),
        Offset(rect.right - radius, rect.bottom), paint);
    canvas.drawLine(Offset(rect.right, rect.bottom - cornerLength),
        Offset(rect.right, rect.bottom - radius), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
