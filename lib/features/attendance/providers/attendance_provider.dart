import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/attendance_repository.dart';
import '../../../shared/models/zone_model.dart';

final attendanceRepositoryProvider = Provider((ref) => AttendanceRepository());

final employeeZonesProvider = FutureProvider.family<List<ZoneModel>, String>(
  (ref, groupId) async {
    return ref.read(attendanceRepositoryProvider).getEmployeeZones(groupId);
  },
);
