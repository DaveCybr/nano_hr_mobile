import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
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
        userLat, userLng, zone.latitude, zone.longitude);
  }

  String determineLocationStatus(
      double userLat, double userLng, List<ZoneModel> zones) {
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
    required String storedFaceToken,
  }) async {
    final detectRes = await http.post(
      Uri.parse('${AppConstants.faceppBaseUrl}/detect'),
      body: {
        'api_key': AppConstants.faceppApiKey,
        'api_secret': AppConstants.faceppApiSecret,
        'image_base64': base64Image,
        'return_attributes': 'none',
      },
    );
    final detectData = jsonDecode(detectRes.body);
    final faces = detectData['faces'] as List?;
    if (faces == null || faces.isEmpty) {
      return {
        'verified': false,
        'confidence': 0.0,
        'error': 'Wajah tidak terdeteksi'
      };
    }
    final newFaceToken = faces[0]['face_token'];
    final compareRes = await http.post(
      Uri.parse('${AppConstants.faceppBaseUrl}/compare'),
      body: {
        'api_key': AppConstants.faceppApiKey,
        'api_secret': AppConstants.faceppApiSecret,
        'face_token1': storedFaceToken,
        'face_token2': newFaceToken,
      },
    );
    final compareData = jsonDecode(compareRes.body);
    final confidence = (compareData['confidence'] as num?)?.toDouble() ?? 0.0;
    return {
      'verified': confidence >= 76.5,
      'confidence': confidence,
      'face_token': newFaceToken,
    };
  }

  String determineCheckInStatus(
      {required String? scheduleIn, required int toleranceMinutes}) {
    if (scheduleIn == null) return 'others';
    final now = DateTime.now();
    final parts = scheduleIn.split(':');
    final scheduleTime = DateTime(now.year, now.month, now.day,
        int.parse(parts[0]), int.parse(parts[1]));
    final diffMinutes = now.difference(scheduleTime).inMinutes;
    if (diffMinutes <= 0) return 'on_time';
    if (diffMinutes <= toleranceMinutes) return 'in_tolerance';
    return 'late';
  }

  String determineCheckOutStatus({required String? scheduleOut}) {
    if (scheduleOut == null) return 'on_time';
    final now = DateTime.now();
    final parts = scheduleOut.split(':');
    final scheduleTime = DateTime(now.year, now.month, now.day,
        int.parse(parts[0]), int.parse(parts[1]));
    if (now.isBefore(scheduleTime)) return 'early_check_out';
    return 'on_time';
  }

  Future<String> uploadAttendancePhoto({
    required String employeeId,
    required String type,
    required Uint8List imageBytes,
  }) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final fileName = 'attendance_${employeeId}_${today}_$type.jpg';
    await supabase.storage.from('attendance-photos').uploadBinary(
        fileName, imageBytes,
        fileOptions:
            const FileOptions(contentType: 'image/jpeg', upsert: true));
    return supabase.storage.from('attendance-photos').getPublicUrl(fileName);
  }

  Future<void> checkIn({
    required String employeeId,
    required String zoneId,
    required double lat,
    required double lng,
    required String locationStatus,
    required String statusIn,
    required bool faceVerified,
    required double faceConfidence,
    required String? reasonIn,
    String? photoUrl,
  }) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final now = DateTime.now().toIso8601String();
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
    }, onConflict: 'employee_id,attendance_date');
  }

  Future<void> checkOut({
    required String attendanceId,
    required String zoneId,
    required double lat,
    required double lng,
    required String locationStatus,
    required String statusOut,
    required bool faceVerified,
    required double faceConfidence,
    required String? reasonOut,
  }) async {
    final now = DateTime.now().toIso8601String();
    await supabase.from('attendances').update({
      'zone_out_id': zoneId,
      'time_out': now,
      'status_out': statusOut,
      'location_out_status': locationStatus,
      'lat_out': lat,
      'lng_out': lng,
      'face_verified': faceVerified,
      'face_confidence': faceConfidence,
      'reason_out': reasonOut,
    }).eq('id', attendanceId);
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
      throw Exception(
          'Izin lokasi ditolak permanen. Aktifkan di pengaturan.');
    }
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }
}
