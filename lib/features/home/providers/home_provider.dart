import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/home_repository.dart';
import '../../../shared/models/employee_model.dart';
import '../../../shared/models/attendance_model.dart';

final homeRepositoryProvider = Provider((ref) => HomeRepository());

final currentEmployeeProvider = FutureProvider<EmployeeModel?>((ref) async {
  return ref.read(homeRepositoryProvider).getCurrentEmployee();
});

final todayAttendanceProvider = FutureProvider.family<AttendanceModel?, String>(
  (ref, employeeId) async {
    return ref.read(homeRepositoryProvider).getTodayAttendance(employeeId);
  },
);

final recentAttendancesProvider = FutureProvider.family<List<AttendanceModel>, String>(
  (ref, employeeId) async {
    return ref.read(homeRepositoryProvider).getRecentAttendances(employeeId);
  },
);

final todayScheduleProvider =
    FutureProvider.family<Map<String, String?>, Map<String, dynamic>>(
  (ref, params) async {
    final repo = ref.read(homeRepositoryProvider);
    return repo.getTodaySchedule(
      params['employee_id'] as String,
      params['group'] as Map<String, dynamic>?,
    );
  },
);

final monthlySummaryProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
  (ref, employeeId) async {
    return ref.read(homeRepositoryProvider).getMonthlySummary(employeeId);
  },
);
