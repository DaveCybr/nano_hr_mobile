import '../../../core/supabase/supabase_client.dart';
import '../../../shared/models/employee_model.dart';
import '../../../shared/models/attendance_model.dart';

class HomeRepository {
  Future<EmployeeModel?> getCurrentEmployee() async {
    final session = supabase.auth.currentSession;
    if (session == null) return null;
    final data = await supabase
        .from('employees')
        .select('*, group:groups(*), position:positions(name)')
        .eq('auth_user_id', session.user.id)
        .eq('is_active', true)
        .maybeSingle();
    return data != null ? EmployeeModel.fromMap(data) : null;
  }

  Future<AttendanceModel?> getTodayAttendance(String employeeId) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    final data = await supabase
        .from('attendances')
        .select()
        .eq('employee_id', employeeId)
        .eq('attendance_date', today)
        .maybeSingle();
    return data != null ? AttendanceModel.fromMap(data) : null;
  }

  Future<List<AttendanceModel>> getRecentAttendances(String employeeId) async {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final fromDate = sevenDaysAgo.toIso8601String().split('T')[0];
    final data = await supabase
        .from('attendances')
        .select()
        .eq('employee_id', employeeId)
        .gte('attendance_date', fromDate)
        .order('attendance_date', ascending: false)
        .limit(7);
    return (data as List).map((e) => AttendanceModel.fromMap(e)).toList();
  }

  Future<Map<String, String?>> getTodaySchedule(
      String employeeId, Map<String, dynamic>? group) async {
    if (group == null) return {'work_in': null, 'work_out': null};
    final scheduleType = group['schedule_type'] as String? ?? 'regular';
    if (scheduleType == 'shifting') {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final data = await supabase
          .from('schedules')
          .select('*, shift_code:shift_codes(work_in, work_out, title, is_holiday)')
          .eq('employee_id', employeeId)
          .eq('schedule_date', today)
          .maybeSingle();
      if (data == null) return {'work_in': null, 'work_out': null};
      final shift = data['shift_code'] as Map<String, dynamic>?;
      return {
        'work_in': shift?['work_in'],
        'work_out': shift?['work_out'],
        'title': shift?['title'],
      };
    } else {
      final dayNames = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
      final dayKey = dayNames[DateTime.now().weekday % 7];
      return {
        'work_in': group['schedule_in_$dayKey'],
        'work_out': group['schedule_out_$dayKey'],
      };
    }
  }

  Future<Map<String, dynamic>> getMonthlySummary(String employeeId) async {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];
    final lastDay = DateTime(now.year, now.month + 1, 0).toIso8601String().split('T')[0];
    final data = await supabase
        .from('attendances')
        .select('work_minutes, late_minutes, status_in, status_out')
        .eq('employee_id', employeeId)
        .gte('attendance_date', firstDay)
        .lte('attendance_date', lastDay);
    final list = data as List;
    int totalWork = 0;
    int totalLate = 0;
    int lateCount = 0;
    int earlyOutCount = 0;
    for (final row in list) {
      totalWork += (row['work_minutes'] as num?)?.toInt() ?? 0;
      totalLate += (row['late_minutes'] as num?)?.toInt() ?? 0;
      if (row['status_in'] == 'late' || ((row['late_minutes'] as num? ?? 0) > 0)) {
        lateCount++;
      }
      if (row['status_out'] == 'early_check_out') earlyOutCount++;
    }
    return {
      'work_minutes': totalWork,
      'late_minutes': totalLate,
      'late_count': lateCount,
      'early_out_count': earlyOutCount,
    };
  }
}
