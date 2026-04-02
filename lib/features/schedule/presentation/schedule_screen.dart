import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../home/providers/home_provider.dart';
import '../../../shared/models/employee_model.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class _DaySchedule {
  final DateTime date;
  final String? workIn;
  final String? workOut;
  final String? shiftTitle;
  final bool isHoliday;
  final bool isWeekend;

  const _DaySchedule({
    required this.date,
    this.workIn,
    this.workOut,
    this.shiftTitle,
    this.isHoliday = false,
    this.isWeekend = false,
  });

  bool get isWorkday => !isHoliday && !isWeekend && workIn != null;
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _weekScheduleProvider = FutureProvider.family<List<_DaySchedule>,
    (String, Map<String, dynamic>?, DateTime)>(
  (ref, params) async {
    final (employeeId, group, weekStart) = params;
    final scheduleType = group?['schedule_type'] as String? ?? 'regular';
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    if (scheduleType == 'shifting') {
      final from = DateFormat('yyyy-MM-dd').format(days.first);
      final to = DateFormat('yyyy-MM-dd').format(days.last);

      final data = await supabase
          .from('schedules')
          .select(
              '*, shift_code:shift_codes(work_in, work_out, title, is_holiday)')
          .eq('employee_id', employeeId)
          .gte('schedule_date', from)
          .lte('schedule_date', to);

      final recordMap = <String, Map<String, dynamic>>{};
      for (final row in data as List) {
        recordMap[row['schedule_date'] as String] = row;
      }

      return days.map((day) {
        final dateKey = DateFormat('yyyy-MM-dd').format(day);
        final row = recordMap[dateKey];
        final shift = row?['shift_code'] as Map<String, dynamic>?;
        final isWeekend =
            day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
        return _DaySchedule(
          date: day,
          workIn: shift?['work_in'],
          workOut: shift?['work_out'],
          shiftTitle: shift?['title'],
          isHoliday: shift?['is_holiday'] == true,
          isWeekend: isWeekend && shift == null,
        );
      }).toList();
    } else {
      final dayKeys = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
      return days.map((day) {
        final key = dayKeys[day.weekday % 7];
        final workIn = group?['schedule_in_$key'] as String?;
        final workOut = group?['schedule_out_$key'] as String?;
        final isWeekendDay =
            day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
        return _DaySchedule(
          date: day,
          workIn: workIn,
          workOut: workOut,
          isHoliday: workIn == null && !isWeekendDay,
          isWeekend: isWeekendDay && workIn == null,
        );
      }).toList();
    }
  },
);

// ── Screen ────────────────────────────────────────────────────────────────────

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = _getMonday(DateTime.now());
  }

  DateTime _getMonday(DateTime date) =>
      date.subtract(Duration(days: date.weekday - 1));

  void _prevWeek() =>
      setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));

  void _nextWeek() =>
      setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));

  bool get _isCurrentWeek {
    final monday = _getMonday(DateTime.now());
    return _weekStart.year == monday.year &&
        _weekStart.month == monday.month &&
        _weekStart.day == monday.day;
  }

  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Jadwal Kerja'),
      ),
      body: SafeArea(
        top: false,
        child: employeeAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child:
                  Text('Error: $e', style: const TextStyle(color: AppColors.danger))),
          data: (employee) {
            if (employee == null) {
              return const Center(child: Text('Data karyawan tidak ditemukan'));
            }
            return _buildBody(employee);
          },
        ),
      ),
    );
  }

  Widget _buildBody(EmployeeModel employee) {
    final scheduleAsync = ref.watch(
        _weekScheduleProvider((employee.id, employee.group, _weekStart)));

    final weekEnd = _weekStart.add(const Duration(days: 6));
    final weekLabel =
        '${DateFormat('d MMM', 'id_ID').format(_weekStart)} – ${DateFormat('d MMM yyyy', 'id_ID').format(weekEnd)}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              // Week navigator
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.textMuted.withValues(alpha: 0.12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded,
                          color: AppColors.primary),
                      onPressed: _prevWeek,
                    ),
                    Column(
                      children: [
                        Text(
                          _isCurrentWeek ? 'Minggu Ini' : 'Minggu',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textMuted),
                        ),
                        Text(
                          weekLabel,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.onSurface),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.primary),
                      onPressed: _nextWeek,
                    ),
                  ],
                ),
              ),

              // Type chips
              if (employee.group != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    _TypeChip(
                      label: employee.group!['schedule_type'] == 'shifting'
                          ? 'Shifting'
                          : 'Regular',
                      color: employee.group!['schedule_type'] == 'shifting'
                          ? const Color(0xFF7C3AED)
                          : AppColors.primary,
                    ),
                    if (employee.group!['name'] != null) ...[
                      const SizedBox(width: 8),
                      _TypeChip(
                        label: employee.group!['name'] as String,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(_weekScheduleProvider(
                  (employee.id, employee.group, _weekStart)));
            },
            child: scheduleAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => ListView(
                children: [
                  SizedBox(
                    height: 300,
                    child: Center(
                      child: Text('Gagal memuat jadwal: $e',
                          style: const TextStyle(color: AppColors.danger),
                          textAlign: TextAlign.center),
                    ),
                  ),
                ],
              ),
              data: (days) => ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: days.length,
                itemBuilder: (_, i) => _DayCard(day: days[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  final _DaySchedule day;
  const _DayCard({required this.day});

  String _trim(String? t) {
    if (t == null) return '--:--';
    return t.length >= 5 ? t.substring(0, 5) : t;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = day.date.year == now.year &&
        day.date.month == now.month &&
        day.date.day == now.day;
    final isPast =
        day.date.isBefore(DateTime(now.year, now.month, now.day));

    final cardBg = isToday
        ? AppColors.primary.withValues(alpha: 0.05)
        : (day.isWeekend || day.isHoliday)
            ? AppColors.surfaceContainerLow
            : AppColors.surfaceContainerLowest;

    final borderColor = isToday
        ? AppColors.primary.withValues(alpha: 0.4)
        : Colors.transparent;

    String? badge;
    Color badgeColor = AppColors.textMuted;
    if (isToday) {
      badge = 'Hari Ini';
      badgeColor = AppColors.primary;
    } else if (day.isHoliday || day.isWeekend) {
      badge = 'Libur';
      badgeColor = const Color(0xFFE91E63);
    } else if (isPast) {
      badge = 'Selesai';
      badgeColor = AppColors.textMuted;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        children: [
          // Date block
          Container(
            width: 48,
            height: 56,
            decoration: BoxDecoration(
              color: isToday
                  ? AppColors.primary
                  : (day.isWeekend || day.isHoliday)
                      ? AppColors.textMuted.withValues(alpha: 0.12)
                      : AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('d').format(day.date),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isToday ? Colors.white : AppColors.onSurface,
                  ),
                ),
                Text(
                  DateFormat('EEE', 'id_ID').format(day.date),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isToday
                        ? Colors.white.withValues(alpha: 0.8)
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: day.isWorkday
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (day.shiftTitle != null) ...[
                        Text(
                          day.shiftTitle!,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Row(
                        children: [
                          _TimeBlock(
                              label: 'MASUK',
                              time: _trim(day.workIn),
                              color: AppColors.primary),
                          const SizedBox(width: 10),
                          const Icon(Icons.arrow_forward_rounded,
                              size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 10),
                          _TimeBlock(
                              label: 'KELUAR',
                              time: _trim(day.workOut),
                              color: AppColors.orange),
                        ],
                      ),
                    ],
                  )
                : Text(
                    day.isHoliday ? 'Hari Libur' : 'Libur Mingguan',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500),
                  ),
          ),

          if (badge != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(badge,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: badgeColor)),
            ),
        ],
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  final String label;
  final String time;
  final Color color;
  const _TimeBlock(
      {required this.label, required this.time, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.4)),
        Text(time,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color)),
      ],
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final Color color;
  const _TypeChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color)),
    );
  }
}
