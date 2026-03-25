import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/models/attendance_model.dart';
import '../../home/providers/home_provider.dart';
import '../../../core/supabase/supabase_client.dart';

final _historyProvider = FutureProvider.family<List<AttendanceModel>, Map<String, dynamic>>(
  (ref, params) async {
    final employeeId = params['employee_id'] as String;
    final year = params['year'] as int;
    final month = params['month'] as int;

    final firstDay = DateTime(year, month, 1).toIso8601String().split('T')[0];
    final lastDay =
        DateTime(year, month + 1, 0).toIso8601String().split('T')[0];

    final data = await supabase
        .from('attendances')
        .select()
        .eq('employee_id', employeeId)
        .gte('attendance_date', firstDay)
        .lte('attendance_date', lastDay)
        .order('attendance_date', ascending: false);

    return (data as List).map((e) => AttendanceModel.fromMap(e)).toList();
  },
);

class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  ConsumerState<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState
    extends ConsumerState<AttendanceHistoryScreen> {
  late int _selectedYear;
  late int _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
  }

  void _prevMonth() {
    setState(() {
      if (_selectedMonth == 1) {
        _selectedMonth = 12;
        _selectedYear--;
      } else {
        _selectedMonth--;
      }
    });
  }

  void _nextMonth() {
    final now = DateTime.now();
    if (_selectedYear == now.year && _selectedMonth == now.month) return;
    setState(() {
      if (_selectedMonth == 12) {
        _selectedMonth = 1;
        _selectedYear++;
      } else {
        _selectedMonth++;
      }
    });
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _selectedYear == now.year && _selectedMonth == now.month;
  }

  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgPrimary,
        title: const Text('Riwayat Kehadiran'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: employeeAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.danger))),
        data: (employee) {
          if (employee == null) {
            return const Center(
                child: Text('Data karyawan tidak ditemukan',
                    style: AppTextStyles.bodySecondary));
          }
          return _buildContent(employee.id);
        },
      ),
    );
  }

  Widget _buildContent(String employeeId) {
    final historyAsync = ref.watch(_historyProvider({
      'employee_id': employeeId,
      'year': _selectedYear,
      'month': _selectedMonth,
    }));

    return Column(
      children: [
        // Month selector
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded,
                    color: AppColors.primary),
                onPressed: _prevMonth,
              ),
              Text(
                DateFormat('MMMM yyyy', 'id_ID')
                    .format(DateTime(_selectedYear, _selectedMonth)),
                style: AppTextStyles.heading3,
              ),
              IconButton(
                icon: Icon(Icons.chevron_right_rounded,
                    color: _isCurrentMonth
                        ? AppColors.textMuted
                        : AppColors.primary),
                onPressed: _isCurrentMonth ? null : _nextMonth,
              ),
            ],
          ),
        ),

        // Summary strip
        historyAsync.when(
          loading: () => const SizedBox(height: 56),
          error: (_, __) => const SizedBox(height: 56),
          data: (list) => _buildSummaryStrip(list),
        ),

        // List
        Expanded(
          child: historyAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
            error: (e, _) => Center(
                child: Text('Gagal memuat data: $e',
                    style: const TextStyle(color: AppColors.danger),
                    textAlign: TextAlign.center)),
            data: (list) => list.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_busy_rounded,
                            color: AppColors.textMuted, size: 52),
                        SizedBox(height: 12),
                        Text('Tidak ada data kehadiran bulan ini',
                            style: AppTextStyles.bodySecondary),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      ref.invalidate(_historyProvider({
                        'employee_id': employeeId,
                        'year': _selectedYear,
                        'month': _selectedMonth,
                      }));
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: list.length,
                      itemBuilder: (ctx, i) => _buildItem(list[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryStrip(List<AttendanceModel> list) {
    final hadir = list.where((a) => a.hasCheckedIn).length;
    final telat =
        list.where((a) => a.statusIn == 'late').length;
    final earlyOut =
        list.where((a) => a.statusOut == 'early_check_out').length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _summaryTile('Hadir', hadir, AppColors.success),
          Container(width: 1, height: 32, color: AppColors.border),
          _summaryTile('Terlambat', telat, AppColors.warning),
          Container(width: 1, height: 32, color: AppColors.border),
          _summaryTile('Keluar Awal', earlyOut, AppColors.danger),
        ],
      ),
    );
  }

  Widget _summaryTile(String label, int count, Color color) {
    return Column(
      children: [
        Text('$count',
            style: TextStyle(
                color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label,
            style:
                const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }

  Widget _buildItem(AttendanceModel att) {
    DateTime? date;
    try {
      date = DateTime.parse(att.attendanceDate);
    } catch (_) {}

    final dayLabel = date != null
        ? DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date)
        : att.attendanceDate;

    final timeIn = att.timeIn != null
        ? DateFormat('HH:mm').format(DateTime.parse(att.timeIn!).toLocal())
        : '--:--';
    final timeOut = att.timeOut != null
        ? DateFormat('HH:mm').format(DateTime.parse(att.timeOut!).toLocal())
        : '--:--';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dayLabel, style: AppTextStyles.body),
              _statusBadge(att),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _timeChip(Icons.login_rounded, 'Masuk', timeIn,
                  AppColors.primary),
              const SizedBox(width: 12),
              _timeChip(Icons.logout_rounded, 'Keluar', timeOut,
                  AppColors.orange),
              if (att.workMinutes > 0) ...[
                const Spacer(),
                Text(
                  _fmtMinutes(att.workMinutes),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ],
          ),
          if (att.lateMinutes > 0) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.timer_off_rounded,
                  color: AppColors.warning, size: 13),
              const SizedBox(width: 4),
              Text('Terlambat ${_fmtMinutes(att.lateMinutes)}',
                  style: const TextStyle(
                      color: AppColors.warning, fontSize: 11)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _timeChip(IconData icon, String label, String time, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 4),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 10)),
        Text(time,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      ]),
    ]);
  }

  Widget _statusBadge(AttendanceModel att) {
    Color color;
    String label;

    if (!att.hasCheckedIn) {
      color = AppColors.danger;
      label = 'Tidak Hadir';
    } else if (att.statusIn == 'late') {
      color = AppColors.warning;
      label = 'Terlambat';
    } else if (att.statusIn == 'in_tolerance') {
      color = AppColors.primary;
      label = 'Toleransi';
    } else {
      color = AppColors.success;
      label = 'Tepat Waktu';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  String _fmtMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return '${h}j ${m}m';
    return '${m}m';
  }
}
