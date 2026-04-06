import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
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
  String? _employeeId;

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

      if (employee == null || employee.facePhotoUrl == null) {
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
        storedFacePhotoUrl: employee.facePhotoUrl!,
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
        _resultMessage = 'Mohon maaf, terjadi kendala: $e';
        _verified = false;
      });
    }
  }

  Future<void> _doCheckIn(
      dynamic employee,
      AttendanceRepository repo,
      Uint8List bytes,
      double confidence) async {
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
    final lateMinutes = repo.calculateLateMinutes(schedule['work_in']);

    String? photoUrl;
    try {
      photoUrl = await repo.uploadAttendancePhoto(
          employeeId: employee.id, type: 'in', imageBytes: bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Foto tidak tersimpan, absensi tetap tercatat'),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }

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
      lateMinutes: lateMinutes,
      faceVerified: true,
      faceConfidence: confidence,
      reasonIn: reason,
      photoUrl: photoUrl,
    );

    _employeeId = employee.id as String;
    if (mounted) _showSuccessModal(statusIn);
  }

  // ── Late modal ────────────────────────────────────────────────────────────

  Future<String?> _showLateModal(DateTime checkInTime) async {
    final dateLabel =
        DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(checkInTime);
    String selectedCategory = 'Lainnya';
    final noteController = TextEditingController();
    int noteLength = 0;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Dialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.errorContainer,
                    ),
                    child: const Icon(Icons.schedule_rounded,
                        color: AppColors.danger, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('Anda Terlambat',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface,
                          )),
                ]),
                const SizedBox(height: 16),

                // Time chip
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.access_time_rounded,
                          color: AppColors.danger, size: 16),
                      const SizedBox(width: 8),
                      Text(dateLabel,
                          style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              )),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                const Text('Alasan keterlambatan:',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        )),
                const SizedBox(height: 8),

                // Category options
                for (final opt in ['Meeting', 'Insiden', 'Lainnya'])
                  GestureDetector(
                    onTap: () =>
                        setModalState(() => selectedCategory = opt),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selectedCategory == opt
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selectedCategory == opt
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(children: [
                        Icon(
                          selectedCategory == opt
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: selectedCategory == opt
                              ? AppColors.primary
                              : AppColors.textMuted,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(opt,
                            style: TextStyle(
                                fontSize: 14,
                                color: selectedCategory == opt
                                    ? AppColors.primary
                                    : AppColors.onSurface,
                                fontWeight: selectedCategory == opt
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                )),
                      ]),
                    ),
                  ),

                const SizedBox(height: 8),

                // Note field
                TextField(
                  controller: noteController,
                  maxLength: 50,
                  maxLines: 2,
                  onChanged: (v) =>
                      setModalState(() => noteLength = v.length),
                  style: const TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 14,
                      ),
                  decoration: InputDecoration(
                    hintText: 'Beri catatan (opsional)',
                    counterText: '$noteLength/50',
                    counterStyle: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        ),
                  ),
                ),

                const SizedBox(height: 16),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primaryContainer
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: ElevatedButton(
                      onPressed: () {
                        final reason = selectedCategory == 'Lainnya'
                            ? noteController.text.trim()
                            : '$selectedCategory: ${noteController.text.trim()}';
                        Navigator.pop(ctx, reason);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Lanjutkan',
                          style: TextStyle(
                              color: AppColors.onPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              )),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Success modal ─────────────────────────────────────────────────────────

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
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success icon
              Container(
                width: 72, height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFDCFCE7),
                ),
                child: const Icon(Icons.check_rounded,
                    color: Color(0xFF166534), size: 40),
              ),
              const SizedBox(height: 20),
              const Text('Check In Berhasil',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                      )),
              const SizedBox(height: 8),
              Text(msg,
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      ),
                  textAlign: TextAlign.center),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.primaryContainer
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      final empId = _employeeId;
                      if (empId != null) {
                        ref.invalidate(todayAttendanceProvider(empId));
                        ref.invalidate(monthlySummaryProvider(empId));
                        ref.invalidate(recentAttendancesProvider(empId));
                      }
                      ref.invalidate(currentEmployeeProvider);
                      context.go('/home');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Kembali ke Beranda',
                        style: TextStyle(
                            color: AppColors.onPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            )),
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
    final now = DateTime.now();
    final dateLabel =
        DateFormat('d MMMM yyyy  •  HH:mm', 'id_ID').format(now);

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: const Text('Verifikasi Wajah',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                )),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Black base
          const ColoredBox(color: Colors.black),

          // Camera preview — fill screen with cover (portrait-correct)
          if (_cameraReady && _capturedBytes == null)
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

          // Captured photo — contain to preserve proportions
          if (_capturedBytes != null)
            Center(
              child: Image.memory(_capturedBytes!, fit: BoxFit.contain),
            ),

          // Loading indicator
          if (!_cameraReady && _capturedBytes == null)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),

          // Top gradient + date/time
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 160,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
          ),

          if (!_processing)
            Positioned(
              top: 100, left: 0, right: 0,
              child: Column(children: [
                Text(dateLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        )),
                const SizedBox(height: 4),
                const Text('Pastikan wajah Anda terlihat jelas.',
                    style: TextStyle(
                        color: Color(0xFF86EFAC),
                        fontSize: 12,
                        )),
              ]),
            ),

          // Face corner brackets
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
                      style:
                          TextStyle(color: Colors.white, fontSize: 14,
                              )),
                ]),
              ),
            ),

          // Result banner
          if (_resultMessage != null)
            Positioned(
              top: 100, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _verified == true
                      ? AppColors.primary.withValues(alpha: 0.92)
                      : AppColors.danger.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  Icon(
                    _verified == true
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    color: Colors.white, size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_resultMessage!,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            )),
                  ),
                ]),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: 52 + MediaQuery.of(context).padding.bottom, left: 24, right: 24,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_verified == false)
                _CameraButton(
                  label: 'Coba Lagi',
                  icon: Icons.refresh_rounded,
                  onPressed: () => setState(() {
                    _capturedBytes = null;
                    _resultMessage = null;
                    _verified = null;
                  }),
                )
              else if (!_processing && _verified == null) ...[
                GestureDetector(
                  onTap: _captureAndVerify,
                  child: Container(
                    width: 76, height: 76,
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
                            spreadRadius: 4),
                      ],
                    ),
                    child: const Icon(
                        Icons.face_retouching_natural_rounded,
                        color: Colors.white,
                        size: 36),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                    'Posisikan wajah dalam bingkai lalu tekan tombol',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        ),
                    textAlign: TextAlign.center),
              ],
            ]),
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

    return SizedBox(
      width: size,
      height: size * 1.25,
      child: Stack(children: [
        Positioned(
            top: 0, left: 0,
            child: CustomPaint(
                size: const Size(len + r, len + r),
                painter: _CornerPainter(
                    topLeft: true, color: c, thick: thick, len: len, r: r))),
        Positioned(
            top: 0, right: 0,
            child: CustomPaint(
                size: const Size(len + r, len + r),
                painter: _CornerPainter(
                    topRight: true, color: c, thick: thick, len: len, r: r))),
        const Positioned(
            bottom: 0, left: 0,
            child: CustomPaint(
                size: Size(len + r, len + r),
                painter: _CornerPainter(
                    bottomLeft: true,
                    color: c,
                    thick: thick,
                    len: len,
                    r: r))),
        const Positioned(
            bottom: 0, right: 0,
            child: CustomPaint(
                size: Size(len + r, len + r),
                painter: _CornerPainter(
                    bottomRight: true,
                    color: c,
                    thick: thick,
                    len: len,
                    r: r))),
      ]),
    );
  }
}

// ── Camera action button ──────────────────────────────────────────────────────

class _CameraButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _CameraButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.15),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
          side: const BorderSide(color: Colors.white30),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                
                fontSize: 15)),
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
