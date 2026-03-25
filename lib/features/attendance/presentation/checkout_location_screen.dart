import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/models/zone_model.dart';
import '../../../shared/widgets/app_button.dart';
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
  bool _submitting = false;
  String? _error;
  String _userAddress = 'Mendapatkan alamat...';
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  Future<void> _getLocation() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
        if (d < minDist) {
          minDist = d;
          nearest = z;
        }
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
        _mapController.move(
            LatLng(position.latitude, position.longitude), 16);
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _geocodeUserLocation(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = <String>[
          if (p.street != null && p.street!.isNotEmpty) p.street!,
          if (p.subLocality != null && p.subLocality!.isNotEmpty)
            p.subLocality!,
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
    if (_currentPosition == null || _nearestZone == null || _submitting) return;

    final employee = await ref.read(currentEmployeeProvider.future);
    if (employee == null) return;

    final repo = AttendanceRepository();
    final schedule = await ref
        .read(homeRepositoryProvider)
        .getTodaySchedule(employee.id, employee.group);
    final statusOut =
        repo.determineCheckOutStatus(scheduleOut: schedule['work_out']);

    String? reason;
    if (statusOut == 'early_check_out' && mounted) {
      reason = await _showEarlyCheckoutModal(schedule['work_out']);
      if (reason == null) return; // user cancelled
    }

    final attendanceData =
        await ref.read(homeRepositoryProvider).getTodayAttendance(employee.id);
    if (attendanceData == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Belum ada data check in hari ini'),
            backgroundColor: AppColors.danger));
      }
      return;
    }

    setState(() => _submitting = true);
    try {
      await repo.checkOut(
        attendanceId: attendanceData.id,
        zoneId: _nearestZone!.id,
        lat: _currentPosition!.latitude,
        lng: _currentPosition!.longitude,
        locationStatus: _locationStatus ?? 'out_of_area',
        statusOut: statusOut,
        faceVerified: false,
        faceConfidence: 0,
        reasonOut: reason,
      );

      ref.invalidate(currentEmployeeProvider);
      ref.invalidate(todayAttendanceProvider(employee.id));

      if (mounted) _showSuccessModal(statusOut);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Check out gagal: $e'),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String?> _showEarlyCheckoutModal(String? scheduleOut) async {
    final timeLabel =
        scheduleOut != null ? scheduleOut.substring(0, 5) : '--:--';
    final dateLabel =
        DateFormat('d MMM yyyy', 'id_ID').format(DateTime.now());
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: EdgeInsets.zero,
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Illustration
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Stack(alignment: Alignment.center, children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.bgCardLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.alarm_rounded,
                      color: AppColors.warning, size: 48),
                ),
                Positioned(
                  right: 100,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.logout_rounded,
                        color: Colors.white, size: 18),
                  ),
                ),
              ]),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.error_rounded,
                          color: AppColors.danger, size: 20),
                      SizedBox(width: 8),
                      Text('Keluar Lebih Awal',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 12),
                    // Schedule box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(children: [
                        const Text('Jadwal Check Out:',
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('$dateLabel, $timeLabel',
                            style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 13,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Anda Check Out sebelum jam kerja selesai.\nMohon isi alasan Anda dibawah.',
                      style: AppTextStyles.bodySecondary,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          hintText: 'Alasan keluar lebih awal'),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, null),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text('Batal'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.pop(ctx, controller.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text('Check Out'),
                        ),
                      ),
                    ]),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  void _showSuccessModal(String statusOut) {
    final msg = statusOut == 'early_check_out'
        ? 'Check out berhasil dengan status Keluar Lebih Awal.'
        : 'Check out berhasil tepat waktu!';
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
          Text('Check Out Berhasil',
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
    final mapCenter = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : _nearestZone != null
            ? LatLng(_nearestZone!.latitude, _nearestZone!.longitude)
            : const LatLng(-8.2006, 113.6793);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgPrimary,
        title: const Text('Check Out Lokasi'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.refresh_rounded, color: AppColors.primary),
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
                color: AppColors.primary),
            onPressed: () {
              if (_currentPosition != null) {
                _mapController.move(
                    LatLng(_currentPosition!.latitude,
                        _currentPosition!.longitude),
                    16);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: mapCenter, initialZoom: 16),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.nano.hr_mobile',
                ),
                CircleLayer(
                  circles: _zones
                      .map((z) => CircleMarker(
                            point: LatLng(z.latitude, z.longitude),
                            radius: z.radiusMeters.toDouble(),
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderColor:
                                AppColors.primary.withValues(alpha: 0.7),
                            borderStrokeWidth: 2,
                            useRadiusInMeter: true,
                          ))
                      .toList(),
                ),
                MarkerLayer(
                  markers: _zones
                      .map((z) => Marker(
                            point: LatLng(z.latitude, z.longitude),
                            width: 40, height: 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.bgCard,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.primary, width: 2),
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
                      width: 16, height: 16,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.success,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ]),
              ],
            ),
          ),

          // Bottom panel
          Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            decoration: const BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)),
                  )
                else if (_error != null)
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!,
                        style: const TextStyle(color: AppColors.danger),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    AppButton(
                        label: 'Coba Lagi',
                        onPressed: _getLocation,
                        icon: Icons.refresh_rounded),
                  ])
                else ...[
                  if (_nearestZone != null) ...[
                    const Text('Lokasi Kantor',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.business_rounded,
                          color: AppColors.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(_nearestZone!.officeName,
                              style: AppTextStyles.body)),
                    ]),
                    if (_nearestZone!.officeAddress != null) ...[
                      const SizedBox(height: 6),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.place_rounded,
                                color: AppColors.textMuted, size: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_nearestZone!.officeAddress!,
                                  style: AppTextStyles.bodySecondary,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                    ],
                    const SizedBox(height: 14),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 14),
                  ],
                  const Text('Lokasi Kamu saat ini',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.bgCardLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      const Icon(Icons.location_on_rounded,
                          color: AppColors.success, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(_userAddress,
                              style: AppTextStyles.bodySecondary)),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    label: 'Check Out',
                    onPressed: _currentPosition != null &&
                            _nearestZone != null &&
                            !_submitting
                        ? _doCheckout
                        : null,
                    loading: _submitting,
                    icon: Icons.logout_rounded,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
