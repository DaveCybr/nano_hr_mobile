class AttendanceModel {
  final String id;
  final String employeeId;
  final String attendanceDate;
  final String? timeIn;
  final String? timeOut;
  final String? statusIn;
  final String? statusOut;
  final String? locationInStatus;
  final String? locationOutStatus;
  final double? latIn;
  final double? lngIn;
  final double? latOut;
  final double? lngOut;
  final String? reasonIn;
  final String? reasonOut;
  final bool faceVerified;
  final double? faceConfidence;
  final int workMinutes;
  final int lateMinutes;
  final String? photoInUrl;

  const AttendanceModel({
    required this.id,
    required this.employeeId,
    required this.attendanceDate,
    this.timeIn,
    this.timeOut,
    this.statusIn,
    this.statusOut,
    this.locationInStatus,
    this.locationOutStatus,
    this.latIn,
    this.lngIn,
    this.latOut,
    this.lngOut,
    this.reasonIn,
    this.reasonOut,
    this.faceVerified = false,
    this.faceConfidence,
    this.workMinutes = 0,
    this.lateMinutes = 0,
    this.photoInUrl,
  });

  factory AttendanceModel.fromMap(Map<String, dynamic> map) {
    return AttendanceModel(
      id: map['id'] ?? '',
      employeeId: map['employee_id'] ?? '',
      attendanceDate: map['attendance_date'] ?? '',
      timeIn: map['time_in'],
      timeOut: map['time_out'],
      statusIn: map['status_in'],
      statusOut: map['status_out'],
      locationInStatus: map['location_in_status'],
      locationOutStatus: map['location_out_status'],
      latIn: (map['lat_in'] as num?)?.toDouble(),
      lngIn: (map['lng_in'] as num?)?.toDouble(),
      latOut: (map['lat_out'] as num?)?.toDouble(),
      lngOut: (map['lng_out'] as num?)?.toDouble(),
      reasonIn: map['reason_in'],
      reasonOut: map['reason_out'],
      faceVerified: map['face_verified'] ?? false,
      faceConfidence: (map['face_confidence'] as num?)?.toDouble(),
      workMinutes: map['work_minutes'] ?? 0,
      lateMinutes: map['late_minutes'] ?? 0,
      photoInUrl: map['photo_in_url'],
    );
  }

  bool get hasCheckedIn => timeIn != null;
  bool get hasCheckedOut => timeOut != null;
}
