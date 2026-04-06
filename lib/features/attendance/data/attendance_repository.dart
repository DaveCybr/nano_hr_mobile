import 'dart:convert';
import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../../core/supabase/supabase_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/models/zone_model.dart';

class AttendanceRepository {
  Future<List<ZoneModel>> getEmployeeZones(String groupId) async {
    final data = await supabase
        .from('group_zones')
        .select('zone:zones(*)')
        .eq('group_id', groupId);
    return (data as List)
        .map((e) => ZoneModel.fromMap(e['zone'] as Map<String, dynamic>))
        .toList();
  }

  double distanceToZone(double userLat, double userLng, ZoneModel zone) {
    return Geolocator.distanceBetween(
      userLat,
      userLng,
      zone.latitude,
      zone.longitude,
    );
  }

  String determineLocationStatus(
    double userLat,
    double userLng,
    List<ZoneModel> zones,
  ) {
    if (zones.isEmpty) return 'out_of_area';
    double minDistance = double.infinity;
    ZoneModel? nearestZone;
    for (final zone in zones) {
      final dist = distanceToZone(userLat, userLng, zone);
      if (dist < minDistance) {
        minDistance = dist;
        nearestZone = zone;
      }
    }
    if (nearestZone == null) return 'out_of_area';
    if (minDistance <= nearestZone.radiusMeters) return 'in_area';
    if (minDistance <= nearestZone.radiusMeters * 1.5) return 'tolerance';
    return 'out_of_area';
  }

  Future<Map<String, dynamic>> verifyFace({
    required String base64Image,
    required String storedFacePhotoUrl,
  }) async {
    final compareRes = await http.post(
      Uri.parse('${AppConstants.faceppBaseUrl}/compare'),
      body: {
        'api_key': AppConstants.faceppApiKey,
        'api_secret': AppConstants.faceppApiSecret,
        'image_url1': storedFacePhotoUrl,
        'image_base64_2': base64Image,
      },
    );
    final compareData = jsonDecode(compareRes.body);
    if (compareData['error_message'] != null) {
      final msg = compareData['error_message'] as String;
      if (msg.contains('INVALID_IMAGE') || msg.contains('NO_FACE_FOUND')) {
        return {
          'verified': false,
          'confidence': 0.0,
          'error': 'Wajah tidak terdeteksi. Pastikan pencahayaan cukup.',
        };
      }
      return {
        'verified': false,
        'confidence': 0.0,
        'error': 'Verifikasi gagal: $msg',
      };
    }
    final confidence = (compareData['confidence'] as num?)?.toDouble() ?? 0.0;
    return {
      'verified': confidence >= 76.5,
      'confidence': confidence,
    };
  }

  String determineCheckInStatus({
    required String? scheduleIn,
    required int toleranceMinutes,
  }) {
    if (scheduleIn == null) return 'others';
    final now = DateTime.now();
    final parts = scheduleIn.split(':');
    final scheduleTime = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    final diffMinutes = now.difference(scheduleTime).inMinutes;
    if (diffMinutes <= 0) return 'on_time';
    if (diffMinutes <= toleranceMinutes) return 'in_tolerance';
    return 'late';
  }

  String determineCheckOutStatus({required String? scheduleOut}) {
    if (scheduleOut == null) return 'on_time';
    final now = DateTime.now();
    final parts = scheduleOut.split(':');
    final scheduleTime = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    if (now.isBefore(scheduleTime)) return 'early_check_out';
    return 'on_time';
  }

  Future<String> uploadAttendancePhoto({
    required String employeeId,
    required String type,
    required Uint8List imageBytes,
  }) async {
    final session = supabase.auth.currentSession;
    if (session == null) throw Exception('Tidak ada sesi login');
    final today = DateTime.now().toIso8601String().split('T')[0];
    final fileName = 'attendance_${employeeId}_${today}_$type.jpg';
    final response = await http.post(
      Uri.parse(
        '${AppConstants.supabaseUrl}/storage/v1/object/attendance-photos/$fileName',
      ),
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'apikey': AppConstants.supabaseAnonKey,
        'Content-Type': 'image/jpeg',
        'x-upsert': 'true',
      },
      body: imageBytes,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Upload foto gagal: ${response.statusCode} - ${response.body}',
      );
    }
    return '${AppConstants.supabaseUrl}/storage/v1/object/public/attendance-photos/$fileName';
  }

  /// Calculates how many minutes late the employee is.
  /// Returns 0 if on time or no schedule.
  int calculateLateMinutes(String? scheduleIn) {
    if (scheduleIn == null) return 0;
    final parts = scheduleIn.split(':');
    final now = DateTime.now();
    final scheduleTime = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    final diff = now.difference(scheduleTime).inMinutes;
    return diff > 0 ? diff : 0;
  }

  Future<void> checkIn({
    required String employeeId,
    required String zoneId,
    required double lat,
    required double lng,
    required String locationStatus,
    required String statusIn,
    required int lateMinutes,
    required bool faceVerified,
    required double faceConfidence,
    required String? reasonIn,
    String? photoUrl,
  }) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final now = DateTime.now().toUtc().toIso8601String();
    await supabase.from('attendances').upsert({
      'employee_id': employeeId,
      'zone_in_id': zoneId,
      'attendance_date': today,
      'time_in': now,
      'status_in': statusIn,
      'location_in_status': locationStatus,
      'lat_in': lat,
      'lng_in': lng,
      'face_verified': faceVerified,
      'face_confidence': faceConfidence,
      'reason_in': reasonIn,
      'late_minutes': lateMinutes,
      if (photoUrl != null) 'photo_in_url': photoUrl,
    }, onConflict: 'employee_id,attendance_date');
  }

  Future<void> checkOut({
    required String attendanceId,
    required String employeeId,
    required String zoneId,
    required double lat,
    required double lng,
    required String locationStatus,
    required String statusOut,
    required bool faceVerified,
    required double faceConfidence,
    required String? reasonOut,
    required String? timeIn,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final now = nowUtc.toIso8601String();

    int workMinutes = 0;
    if (timeIn != null) {
      final checkInTime = DateTime.parse(timeIn);
      workMinutes = nowUtc.difference(checkInTime).inMinutes.clamp(0, 9999);
    }

    final result = await supabase
        .from('attendances')
        .update({
          'zone_out_id': zoneId,
          'time_out': now,
          'status_out': statusOut,
          'location_out_status': locationStatus,
          'lat_out': lat,
          'lng_out': lng,
          'face_verified': faceVerified,
          'face_confidence': faceConfidence,
          'reason_out': reasonOut,
          'work_minutes': workMinutes,
        })
        .eq('id', attendanceId)
        .eq('employee_id', employeeId)
        .select();
    if (result.isEmpty) {
      print(
        'Gagal menyimpan checkout: data absensi tidak ditemukan (id=$attendanceId)',
      );
      throw Exception(
        'Gagal menyimpan checkout: data absensi tidak ditemukan (id=$attendanceId)',
      );
    }
  }

  Future<Position> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('GPS tidak aktif');
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Izin lokasi ditolak');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Izin lokasi ditolak permanen. Aktifkan di pengaturan.');
    }
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }
}
