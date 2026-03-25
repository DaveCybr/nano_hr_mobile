import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/app_button.dart';
import '../../home/providers/home_provider.dart';
import '../data/attendance_repository.dart';

class CheckinFaceScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> locationData;
  const CheckinFaceScreen({super.key, required this.locationData});

  @override
  ConsumerState<CheckinFaceScreen> createState() => _CheckinFaceScreenState();
}

class _CheckinFaceScreenState extends ConsumerState<CheckinFaceScreen> {
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _processing = false;
  String? _resultMessage;
  bool? _verified;
  Uint8List? _capturedBytes;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller =
          CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _cameraController = controller;
        _cameraReady = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _resultMessage = 'Kamera tidak tersedia: $e';
          _verified = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _captureAndVerify() async {
    if (_cameraController == null || !_cameraReady || _processing) return;
    setState(() {
      _processing = true;
      _resultMessage = null;
      _verified = null;
      _capturedBytes = null;
    });
    try {
      final image = await _cameraController!.takePicture();
      final bytes = await image.readAsBytes();
      setState(() => _capturedBytes = bytes);

      final base64Image = base64Encode(bytes);
      final employee = await ref.read(currentEmployeeProvider.future);

      if (employee == null || employee.faceToken == null) {
        setState(() {
          _processing = false;
          _resultMessage = 'Data wajah tidak ditemukan. Silakan enroll ulang.';
          _verified = false;
        });
        return;
      }

      final repo = AttendanceRepository();
      final result = await repo.verifyFace(
        base64Image: base64Image,
        storedFaceToken: employee.faceToken!,
      );

      final isVerified = result['verified'] as bool? ?? false;
      final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
      final error = result['error'] as String?;

      setState(() {
        _verified = isVerified;
        _resultMessage = error ??
            (isVerified
                ? 'Wajah terverifikasi (${confidence.toStringAsFixed(1)}%)'
                : 'Wajah tidak cocok (${confidence.toStringAsFixed(1)}%). Coba lagi.');
        _processing = false;
      });

      if (isVerified) await _doCheckIn(employee, repo, bytes, confidence);
    } catch (e) {
      setState(() {
        _processing = false;
        _resultMessage = 'Terjadi kesalahan: $e';
        _verified = false;
      });
    }
  }

  Future<void> _doCheckIn(
      dynamic employee, AttendanceRepository repo, Uint8List bytes, double confidence) async {
    final lat = widget.locationData['lat'] as double;
    final lng = widget.locationData['lng'] as double;
    final locationStatus = widget.locationData['location_status'] as String;
    final zoneId = widget.locationData['zone_id'] as String;

    final schedule = await ref
        .read(homeRepositoryProvider)
        .getTodaySchedule(employee.id, employee.group);
    final toleranceMinutes =
        (employee.group?['tolerance_minutes'] as num?)?.toInt() ?? 0;
    final statusIn = repo.determineCheckInStatus(
        scheduleIn: schedule['work_in'], toleranceMinutes: toleranceMinutes);

    String? photoUrl;
    try {
      photoUrl = await repo.uploadAttendancePhoto(
          employeeId: employee.id, type: 'in', imageBytes: bytes);
    } catch (_) {}

    String? reason;
    if (statusIn == 'late' && mounted) {
      reason = await _showLateModal(DateTime.now());
    }

    await repo.checkIn(
      employeeId: employee.id,
      zoneId: zoneId,
      lat: lat,
      lng: lng,
      locationStatus: locationStatus,
      statusIn: statusIn,
      faceVerified: true,
      faceConfidence: confidence,
      reasonIn: reason,
      photoUrl: photoUrl,
    );

    ref.invalidate(currentEmployeeProvider);
    ref.invalidate(todayAttendanceProvider(employee.id as String));

    if (mounted) _showSuccessModal(statusIn);
  }

  // ── Late modal with radio buttons ──────────────────────────────────────────
  Future<String?> _showLateModal(DateTime checkInTime) async {
    final dateLabel = DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(checkInTime);
    String selectedCategory = 'Lainnya';
    final noteController = TextEditingController();
    int noteLength = 0;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: AppColors.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          title: const Row(children: [
            Icon(Icons.error_rounded, color: AppColors.danger, size: 22),
            SizedBox(width: 8),
            Text('Anda telat',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Check-in time box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(children: [
                  const Text('Check In:',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(dateLabel,
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
              const SizedBox(height: 14),
              const Text(
                'Mohon cantumkan alasan mengapa Anda telat:',
                style: AppTextStyles.bodySecondary,
              ),
              const SizedBox(height: 10),
              // Radio options
              for (final opt in ['Meeting', 'Insiden', 'Lainnya'])
                RadioListTile<String>(
                  value: opt,
                  groupValue: selectedCategory,
                  onChanged: (v) =>
                      setModalState(() => selectedCategory = v ?? 'Lainnya'),
                  title: Text(opt,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13)),
                  activeColor: AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              const SizedBox(height: 8),
              // Note field with counter
              TextField(
                controller: noteController,
                maxLength: 50,
                maxLines: 2,
                onChanged: (v) => setModalState(() => noteLength = v.length),
                decoration: InputDecoration(
                  hintText: 'Beri catatan disini',
                  counterText: '$noteLength/50',
                  counterStyle: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    final reason = selectedCategory == 'Lainnya'
                        ? noteController.text.trim()
                        : '$selectedCategory: ${noteController.text.trim()}';
                    Navigator.pop(ctx, reason);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Lanjut',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessModal(String statusIn) {
    String msg;
    if (statusIn == 'late') {
      msg = 'Check in berhasil dengan status Terlambat.';
    } else if (statusIn == 'in_tolerance') {
      msg = 'Check in berhasil dalam waktu toleransi.';
    } else {
      msg = 'Check in berhasil tepat waktu!';
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.check_circle_rounded, color: AppColors.success),
          SizedBox(width: 8),
          Text('Check In Berhasil',
              style: TextStyle(color: AppColors.textPrimary)),
        ]),
        content: Text(msg, style: AppTextStyles.bodySecondary),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/home');
            },
            child: const Text('Kembali ke Beranda'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateLabel =
        DateFormat('d MMMM yyyy, HH:mm', 'id_ID').format(now);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Verifikasi Wajah Anda',
            style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera / captured preview
          if (_cameraReady && _capturedBytes == null)
            CameraPreview(_cameraController!),
          if (_capturedBytes != null)
            Image.memory(_capturedBytes!, fit: BoxFit.cover),
          if (!_cameraReady && _capturedBytes == null)
            const Center(
                child: CircularProgressIndicator(color: AppColors.primary)),

          // Date/time + subtitle at top
          if (!_processing)
            Positioned(
              top: 16,
              left: 0, right: 0,
              child: Column(children: [
                Text(dateLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(blurRadius: 8, color: Colors.black54)
                        ])),
                const SizedBox(height: 4),
                const Text('Pastikan wajah Anda terlihat jelas.',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        shadows: [
                          Shadow(blurRadius: 8, color: Colors.black54)
                        ])),
              ]),
            ),

          // Corner-bracket face guide (only when idle)
          if (_cameraReady && !_processing && _verified == null)
            Center(child: _buildCornerBrackets()),

          // Processing overlay
          if (_processing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text('Memverifikasi wajah...',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                ]),
              ),
            ),

          // Result banner
          if (_resultMessage != null)
            Positioned(
              top: 80, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _verified == true
                      ? AppColors.success.withValues(alpha: 0.9)
                      : AppColors.danger.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_resultMessage!,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: 48, left: 24, right: 24,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_verified == false)
                AppButton(
                    label: 'Coba Lagi',
                    onPressed: () => setState(() {
                          _capturedBytes = null;
                          _resultMessage = null;
                          _verified = null;
                        }),
                    icon: Icons.refresh_rounded)
              else if (!_processing && _verified == null) ...[
                GestureDetector(
                  onTap: _captureAndVerify,
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.9),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4),
                            blurRadius: 20,
                            spreadRadius: 2),
                      ],
                    ),
                    child: const Icon(Icons.face_retouching_natural_rounded,
                        color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('Posisikan wajah dalam bingkai lalu tekan tombol',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                    textAlign: TextAlign.center),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  // Corner bracket guide widget
  Widget _buildCornerBrackets() {
    const size = 220.0;
    const thick = 3.0;
    const len = 32.0;
    const r = 8.0;
    const c = AppColors.primary;

    return SizedBox(
      width: size,
      height: size * 1.25,
      child: Stack(children: [
        // Top-left
        Positioned(
            top: 0, left: 0,
            child: CustomPaint(
                size: const Size(len + r, len + r),
                painter: _CornerPainter(
                    topLeft: true, color: c, thick: thick, len: len, r: r))),
        // Top-right
        Positioned(
            top: 0, right: 0,
            child: CustomPaint(
                size: const Size(len + r, len + r),
                painter: _CornerPainter(
                    topRight: true, color: c, thick: thick, len: len, r: r))),
        // Bottom-left
        Positioned(
            bottom: 0, left: 0,
            child: CustomPaint(
                size: const Size(len + r, len + r),
                painter: _CornerPainter(
                    bottomLeft: true, color: c, thick: thick, len: len, r: r))),
        // Bottom-right
        Positioned(
            bottom: 0, right: 0,
            child: CustomPaint(
                size: const Size(len + r, len + r),
                painter: _CornerPainter(
                    bottomRight: true, color: c, thick: thick, len: len, r: r))),
      ]),
    );
  }
}

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
      path.arcToPoint(Offset(r, 0),
          radius: Radius.circular(r), clockwise: true);
      path.lineTo(len, 0);
    } else if (topRight) {
      path.moveTo(size.width - len, 0);
      path.lineTo(size.width - r, 0);
      path.arcToPoint(Offset(size.width, r),
          radius: Radius.circular(r), clockwise: true);
      path.lineTo(size.width, len);
    } else if (bottomLeft) {
      path.moveTo(0, size.height - len);
      path.lineTo(0, size.height - r);
      path.arcToPoint(Offset(r, size.height),
          radius: Radius.circular(r), clockwise: false);
      path.lineTo(len, size.height);
    } else if (bottomRight) {
      path.moveTo(size.width - len, size.height);
      path.lineTo(size.width - r, size.height);
      path.arcToPoint(Offset(size.width, size.height - r),
          radius: Radius.circular(r), clockwise: false);
      path.lineTo(size.width, size.height - len);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
