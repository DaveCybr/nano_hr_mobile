import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/zone_model.dart';
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
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Check In',
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
                    width: 18,
                    height: 18,
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
                        _currentPosition!.longitude),
                    16);
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Map ───────────────────────────────────────────────────────
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
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderColor:
                                AppColors.primary.withValues(alpha: 0.6),
                            borderStrokeWidth: 2,
                            useRadiusInMeter: true,
                          ))
                      .toList(),
                ),
                MarkerLayer(
                  markers: _zones
                      .map((z) => Marker(
                            point: LatLng(z.latitude, z.longitude),
                            width: 44,
                            height: 44,
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLowest,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.primary, width: 2),
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
                      width: 20,
                      height: 20,
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

          // ── Bottom panel ──────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 36 + MediaQuery.of(context).padding.bottom),
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
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
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
                            style: TextStyle(
                                color: AppColors.danger,
                                fontSize: 13,
                                ),
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
                  // ── Lokasi Kantor ────────────────────────────────────
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
                                    letterSpacing: 0.5,
                                    )),
                            const SizedBox(height: 2),
                            Text(_nearestZone!.officeName,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.onSurface,
                                    )),
                            if (_nearestZone!.officeAddress != null)
                              Text(_nearestZone!.officeAddress!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 16),
                  ],

                  // ── Lokasi Kamu ──────────────────────────────────────
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
                                  letterSpacing: 0.5,
                                  )),
                          const SizedBox(height: 2),
                          Text(_userAddress,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    // Location status chip
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
                          _locationStatus == 'in_area' ? 'Dalam Area' : 'Di Luar Area',
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
                    label: 'Check In Disini',
                    icon: Icons.login_rounded,
                    onPressed: _currentPosition != null && _nearestZone != null
                        ? _proceed
                        : null,
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

// ── Gradient Button ───────────────────────────────────────────────────────────

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const _GradientButton({
    required this.label,
    this.icon,
    this.onPressed,
  });

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
