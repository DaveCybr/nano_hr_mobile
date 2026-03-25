import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/models/zone_model.dart';
import '../../../shared/widgets/app_button.dart';
import '../../home/providers/home_provider.dart';
import '../providers/attendance_provider.dart';
import '../data/attendance_repository.dart';

class CheckinLocationScreen extends ConsumerStatefulWidget {
  const CheckinLocationScreen({super.key});

  @override
  ConsumerState<CheckinLocationScreen> createState() =>
      _CheckinLocationScreenState();
}

class _CheckinLocationScreenState
    extends ConsumerState<CheckinLocationScreen> {
  Position? _currentPosition;
  String? _locationStatus;
  ZoneModel? _nearestZone;
  List<ZoneModel> _zones = [];
  bool _loading = true;
  bool _refreshing = false;
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

  void _proceed() {
    if (_currentPosition == null || _nearestZone == null) return;
    context.push('/checkin/face', extra: {
      'lat': _currentPosition!.latitude,
      'lng': _currentPosition!.longitude,
      'location_status': _locationStatus ?? 'out_of_area',
      'zone_id': _nearestZone!.id,
    });
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
        title: const Text('Check In Lokasi'),
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
          // ── Map ──────────────────────────────────────────
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: mapCenter,
                initialZoom: 16,
              ),
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
                            width: 40,
                            height: 40,
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
                      width: 16,
                      height: 16,
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

          // ── Bottom panel ──────────────────────────────────
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
                // drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    width: 40,
                    height: 4,
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
                  // Lokasi Kantor
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

                  // Lokasi Kamu saat ini
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
                    label: 'Check In Disini',
                    onPressed: _currentPosition != null && _nearestZone != null
                        ? _proceed
                        : null,
                    icon: Icons.login_rounded,
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
