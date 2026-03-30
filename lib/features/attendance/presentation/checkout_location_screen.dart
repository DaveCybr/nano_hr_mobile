import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/zone_model.dart';
import '../../home/providers/home_provider.dart';
import '../providers/attendance_provider.dart';
import '../data/attendance_repository.dart';

class CheckoutLocationScreen extends ConsumerStatefulWidget {
  const CheckoutLocationScreen({super.key});

  @override
  ConsumerState<CheckoutLocationScreen> createState() =>
      _CheckoutLocationScreenState();
}

class _CheckoutLocationScreenState
    extends ConsumerState<CheckoutLocationScreen> {
  Position? _currentPosition;
  String? _locationStatus;
  ZoneModel? _nearestZone;
  List<ZoneModel> _zones = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _processing = false;
  String? _error;
  String _userAddress = 'Mendapatkan alamat...';
  String? _employeeId;
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  Future<void> _getLocation() async {
    setState(() { _loading = true; _error = null; });
    try {
      final repo = AttendanceRepository();
      final position = await repo.getCurrentPosition();

      final employee = await ref.read(currentEmployeeProvider.future);
      List<ZoneModel> zones = [];
      if (employee?.groupId != null) {
        zones = await ref
            .read(attendanceRepositoryProvider)
            .getEmployeeZones(employee!.groupId!);
      }

      double minDist = double.infinity;
      ZoneModel? nearest;
      for (final z in zones) {
        final d = repo.distanceToZone(position.latitude, position.longitude, z);
        if (d < minDist) { minDist = d; nearest = z; }
      }

      setState(() {
        _currentPosition = position;
        _zones = zones;
        _nearestZone = nearest;
        _locationStatus = repo.determineLocationStatus(
            position.latitude, position.longitude, zones);
        _loading = false;
      });

      _geocodeUserLocation(position.latitude, position.longitude);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(LatLng(position.latitude, position.longitude), 16);
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _geocodeUserLocation(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = <String>[
          if (p.street != null && p.street!.isNotEmpty) p.street!,
          if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
          if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
        ];
        setState(() =>
            _userAddress = parts.isNotEmpty ? parts.join(', ') : '$lat, $lng');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _userAddress =
            '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}');
      }
    }
  }

  Future<void> _doCheckout() async {
    if (_currentPosition == null || _nearestZone == null || _processing) return;
    setState(() => _processing = true);

    try {
      final repo = AttendanceRepository();
      final employee = await ref.read(currentEmployeeProvider.future);
      if (employee == null) throw Exception('Data karyawan tidak ditemukan');

      final attendance = await ref
          .read(homeRepositoryProvider)
          .getTodayAttendance(employee.id);
      if (attendance == null) throw Exception('Data absensi hari ini tidak ditemukan');
      if (attendance.id.isEmpty) throw Exception('ID absensi tidak valid — coba refresh halaman');

      final schedule = await ref
          .read(homeRepositoryProvider)
          .getTodaySchedule(employee.id, employee.group);

      final statusOut = repo.determineCheckOutStatus(
          scheduleOut: schedule['work_out']);

      String? reason;
      if (statusOut == 'early_check_out' && mounted) {
        reason = await _showEarlyCheckoutModal(DateTime.now());
        if (reason == null) {
          setState(() => _processing = false);
          return;
        }
      }

      await repo.checkOut(
        attendanceId: attendance.id,
        employeeId: employee.id,
        zoneId: _nearestZone!.id,
        lat: _currentPosition!.latitude,
        lng: _currentPosition!.longitude,
        locationStatus: _locationStatus ?? 'out_of_area',
        statusOut: statusOut,
        faceVerified: false,
        faceConfidence: 0.0,
        reasonOut: reason,
        timeIn: attendance.timeIn,
      );

      _employeeId = employee.id;
      if (mounted) _showSuccessModal(statusOut);
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal checkout: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  // ── Early checkout modal ──────────────────────────────────────────────────

  Future<String?> _showEarlyCheckoutModal(DateTime checkOutTime) async {
    final dateLabel =
        DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(checkOutTime);
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
                  const Text('Checkout Lebih Awal',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.onSurface)),
                ]),
                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                const Text('Alasan checkout lebih awal:',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 8),

                for (final opt in ['Izin', 'Sakit', 'Lainnya'])
                  GestureDetector(
                    onTap: () => setModalState(() => selectedCategory = opt),
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
                                    : FontWeight.normal)),
                      ]),
                    ),
                  ),

                const SizedBox(height: 8),

                TextField(
                  controller: noteController,
                  maxLength: 50,
                  maxLines: 2,
                  onChanged: (v) => setModalState(() => noteLength = v.length),
                  style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Beri catatan (opsional)',
                    counterText: '$noteLength/50',
                    counterStyle: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11),
                  ),
                ),

                const SizedBox(height: 16),

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
                              fontWeight: FontWeight.w600)),
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

  void _showSuccessModal(String statusOut) {
    final msg = statusOut == 'early_check_out'
        ? 'Check out berhasil lebih awal.'
        : 'Check out berhasil tepat waktu!';

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
                width: 72, height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFDCFCE7),
                ),
                child: const Icon(Icons.check_rounded,
                    color: Color(0xFF166534), size: 40),
              ),
              const SizedBox(height: 20),
              const Text('Check Out Berhasil',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface)),
              const SizedBox(height: 8),
              Text(msg,
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
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
                            fontWeight: FontWeight.w600)),
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
    final mapCenter = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : _nearestZone != null
            ? LatLng(_nearestZone!.latitude, _nearestZone!.longitude)
            : const LatLng(-8.2006, 113.6793);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Check Out',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.onSurface,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.onSurface, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.refresh_rounded,
                    color: AppColors.primary, size: 22),
            onPressed: _refreshing
                ? null
                : () async {
                    setState(() => _refreshing = true);
                    await _getLocation();
                    setState(() => _refreshing = false);
                  },
          ),
          IconButton(
            icon: const Icon(Icons.my_location_rounded,
                color: AppColors.primary, size: 22),
            onPressed: () {
              if (_currentPosition != null) {
                _mapController.move(
                    LatLng(_currentPosition!.latitude,
                        _currentPosition!.longitude), 16);
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
        children: [
          // ── Map ─────────────────────────────────────────────────────────
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: mapCenter, initialZoom: 16),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.nano.hr_mobile',
                ),
                CircleLayer(
                  circles: _zones
                      .map((z) => CircleMarker(
                            point: LatLng(z.latitude, z.longitude),
                            radius: z.radiusMeters.toDouble(),
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderColor: AppColors.primary.withValues(alpha: 0.6),
                            borderStrokeWidth: 2,
                            useRadiusInMeter: true,
                          ))
                      .toList(),
                ),
                MarkerLayer(
                  markers: _zones
                      .map((z) => Marker(
                            point: LatLng(z.latitude, z.longitude),
                            width: 44, height: 44,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLowest,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.primary, width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x14006036),
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.business_rounded,
                                  color: AppColors.primary, size: 20),
                            ),
                          ))
                      .toList(),
                ),
                if (_currentPosition != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(_currentPosition!.latitude,
                          _currentPosition!.longitude),
                      width: 20, height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x30006036),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]),
              ],
            ),
          ),

          // ── Bottom panel ────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, 36 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 24,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2)),
                  )
                else if (_error != null)
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline_rounded,
                            color: AppColors.danger, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Mohon maaf, terjadi kendala mendapatkan lokasi.',
                            style: TextStyle(color: AppColors.danger, fontSize: 13),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    _GradientButton(
                      label: 'Coba Lagi',
                      icon: Icons.refresh_rounded,
                      onPressed: _getLocation,
                    ),
                  ])
                else ...[
                  if (_nearestZone != null) ...[
                    Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFE8F5EE),
                        ),
                        child: const Icon(Icons.business_rounded,
                            color: AppColors.primary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Lokasi Kantor',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textMuted,
                                    letterSpacing: 0.5)),
                            const SizedBox(height: 2),
                            Text(_nearestZone!.officeName,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.onSurface)),
                            if (_nearestZone!.officeAddress != null)
                              Text(_nearestZone!.officeAddress!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                  ],

                  Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFE8F5EE),
                      ),
                      child: const Icon(Icons.location_on_rounded,
                          color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Lokasi Kamu',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textMuted,
                                  letterSpacing: 0.5)),
                          const SizedBox(height: 2),
                          Text(_userAddress,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (_locationStatus != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _locationStatus == 'in_area'
                              ? const Color(0xFFDCFCE7)
                              : AppColors.errorContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _locationStatus == 'in_area'
                              ? 'Dalam Area'
                              : 'Di Luar Area',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _locationStatus == 'in_area'
                                ? const Color(0xFF166534)
                                : AppColors.danger,
                          ),
                        ),
                      ),
                  ]),

                  const SizedBox(height: 20),

                  _GradientButton(
                    label: _processing ? 'Memproses...' : 'Check Out Disini',
                    icon: _processing
                        ? Icons.hourglass_top_rounded
                        : Icons.directions_run_rounded,
                    onPressed: _currentPosition != null &&
                            _nearestZone != null &&
                            !_processing
                        ? _doCheckout
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const _GradientButton({required this.label, this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: disabled
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryContainer],
                ),
          color: disabled ? AppColors.surfaceContainerLow : null,
          borderRadius: BorderRadius.circular(100),
          boxShadow: disabled
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x14006036),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
        ),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: const StadiumBorder(),
          ),
          icon: Icon(
            icon ?? Icons.arrow_forward_rounded,
            color: disabled ? AppColors.textMuted : AppColors.onPrimary,
            size: 20,
          ),
          label: Text(
            label,
            style: TextStyle(
              color: disabled ? AppColors.textMuted : AppColors.onPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
