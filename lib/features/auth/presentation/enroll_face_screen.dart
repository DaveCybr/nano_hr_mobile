import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/app_colors.dart';
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
  bool _cameraReady = false;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
      );
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
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final photo = await _cameraController!.takePicture();
      final imageBytes = await File(photo.path).readAsBytes();
      final base64Image = base64Encode(imageBytes);

      // Detect face via Face++
      final detectRes = await http.post(
        Uri.parse('${AppConstants.faceppBaseUrl}/detect'),
        body: {
          'api_key': AppConstants.faceppApiKey,
          'api_secret': AppConstants.faceppApiSecret,
          'image_base64': base64Image,
          'return_attributes': 'none',
        },
      );
      final detectData = jsonDecode(detectRes.body) as Map<String, dynamic>;

      if (detectData['faces'] == null ||
          (detectData['faces'] as List).isEmpty) {
        setState(() {
          _error =
              'Wajah tidak terdeteksi. Pastikan pencahayaan cukup dan wajah terlihat jelas.';
          _processing = false;
        });
        return;
      }

      final faceToken = detectData['faces'][0]['face_token'] as String;

      // Upload foto ke Supabase Storage via direct HTTP
      final session = supabase.auth.currentSession!;
      final userId = session.user.id;
      final fileName = 'face_$userId.jpg';

      await http.delete(
        Uri.parse(
          '${AppConstants.supabaseUrl}/storage/v1/object/employee-photos/$fileName',
        ),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': AppConstants.supabaseAnonKey,
        },
      );

      final uploadResponse = await http.post(
        Uri.parse(
          '${AppConstants.supabaseUrl}/storage/v1/object/employee-photos/$fileName',
        ),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': AppConstants.supabaseAnonKey,
          'Content-Type': 'image/jpeg',
          'x-upsert': 'true',
        },
        body: imageBytes,
      );

      if (uploadResponse.statusCode != 200 &&
          uploadResponse.statusCode != 201) {
        throw Exception(
          'Upload gagal: ${uploadResponse.statusCode} - ${uploadResponse.body}',
        );
      }

      final photoUrl =
          '${AppConstants.supabaseUrl}/storage/v1/object/public/employee-photos/$fileName';

      // Simpan face_token ke tabel employees
      final repo = ref.read(authRepositoryProvider);
      await repo.saveFaceToken(faceToken: faceToken, facePhotoUrl: photoUrl);

      if (!mounted) return;
      _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Terjadi kesalahan: $e';
          _processing = false;
        });
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFDCFCE7),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF166534),
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Wajah Terdaftar!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Data wajah Anda berhasil disimpan.',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryContainer],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.go('/home');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Mulai Gunakan Aplikasi',
                      style: TextStyle(
                        color: AppColors.onPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        title: const Center(
          child: Text(
            'Daftarkan Wajah',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Black base
          const ColoredBox(color: Colors.black),

          // Camera preview — full screen, portrait-correct
          if (_cameraReady)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _cameraController!.value.previewSize!.height,
                  height: _cameraController!.value.previewSize!.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),

          // Camera loading
          if (!_cameraReady && _error == null)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),

          // Camera error (no camera)
          if (_error != null && !_cameraReady)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // Top gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 180,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
          ),

          // Sub-title below AppBar
          if (!_processing)
            const Positioned(
              top: 104,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    'Foto wajah digunakan untuk verifikasi absensi.',
                    style: TextStyle(color: Color(0xFF86EFAC), fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          // Corner brackets
          if (_cameraReady && !_processing)
            Center(child: _buildCornerBrackets()),

          // Processing overlay
          if (_processing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text(
                      'Mendaftarkan wajah...',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),

          // Error banner (post-camera)
          if (_error != null && _cameraReady)
            Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: 52 + MediaQuery.of(context).padding.bottom,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_processing) ...[
                  GestureDetector(
                    onTap: _captureAndEnroll,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primaryContainer,
                            AppColors.primary,
                          ],
                        ),
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.5),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.face_retouching_natural_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Posisikan wajah dalam bingkai lalu tekan tombol',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCornerBrackets() {
    const size = 220.0;
    const thick = 3.0;
    const len = 32.0;
    const r = 8.0;
    const c = AppColors.primary;

    return const SizedBox(
      width: size,
      height: size * 1.25,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: CustomPaint(
              size: Size(len + r, len + r),
              painter: _CornerPainter(
                topLeft: true,
                color: c,
                thick: thick,
                len: len,
                r: r,
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: CustomPaint(
              size: Size(len + r, len + r),
              painter: _CornerPainter(
                topRight: true,
                color: c,
                thick: thick,
                len: len,
                r: r,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: CustomPaint(
              size: Size(len + r, len + r),
              painter: _CornerPainter(
                bottomLeft: true,
                color: c,
                thick: thick,
                len: len,
                r: r,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: CustomPaint(
              size: Size(len + r, len + r),
              painter: _CornerPainter(
                bottomRight: true,
                color: c,
                thick: thick,
                len: len,
                r: r,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Corner bracket painter ────────────────────────────────────────────────────

class _CornerPainter extends CustomPainter {
  final bool topLeft, topRight, bottomLeft, bottomRight;
  final Color color;
  final double thick, len, r;

  const _CornerPainter({
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
    required this.color,
    required this.thick,
    required this.len,
    required this.r,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thick
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    if (topLeft) {
      path.moveTo(0, len);
      path.lineTo(0, r);
      path.arcToPoint(
        Offset(r, 0),
        radius: Radius.circular(r),
        clockwise: true,
      );
      path.lineTo(len, 0);
    } else if (topRight) {
      path.moveTo(size.width - len, 0);
      path.lineTo(size.width - r, 0);
      path.arcToPoint(
        Offset(size.width, r),
        radius: Radius.circular(r),
        clockwise: true,
      );
      path.lineTo(size.width, len);
    } else if (bottomLeft) {
      path.moveTo(0, size.height - len);
      path.lineTo(0, size.height - r);
      path.arcToPoint(
        Offset(r, size.height),
        radius: Radius.circular(r),
        clockwise: false,
      );
      path.lineTo(len, size.height);
    } else if (bottomRight) {
      path.moveTo(size.width - len, size.height);
      path.lineTo(size.width - r, size.height);
      path.arcToPoint(
        Offset(size.width, size.height - r),
        radius: Radius.circular(r),
        clockwise: false,
      );
      path.lineTo(size.width, size.height - len);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
