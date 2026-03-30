import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../home/providers/home_provider.dart';

// ── Provider ─────────────────────────────────────────────────────────────────

final _ringkasanProvider =
    FutureProvider.family<Map<String, dynamic>, (String, int, int)>(
  (ref, params) async {
    final (employeeId, year, month) = params;
    final firstDay = DateTime(year, month, 1).toIso8601String().split('T')[0];
    final lastDay =
        DateTime(year, month + 1, 0).toIso8601String().split('T')[0];

    final data = await supabase
        .from('attendances')
        .select(
            'work_minutes, late_minutes, status_in, status_out, attendance_date, time_in, time_out')
        .eq('employee_id', employeeId)
        .gte('attendance_date', firstDay)
        .lte('attendance_date', lastDay);

    final list = data as List;

    int totalWork = 0;
    int totalLate = 0;
    int hadirCount = 0;
    int tidakHadirCount = 0;
    int lateCount = 0;
    int earlyOutCount = 0;
    int autoCheckoutCount = 0;
    final List<Map<String, dynamic>> weekly = [{}, {}, {}, {}, {}];

    // Count weekdays in month
    int workdays = 0;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    for (int d = 1; d <= daysInMonth; d++) {
      final day = DateTime(year, month, d);
      if (day.weekday != DateTime.saturday &&
          day.weekday != DateTime.sunday) {
        workdays++;
      }
    }

    final recordDates = <String>{};

    for (final row in list) {
      final dateStr = row['attendance_date'] as String;
      recordDates.add(dateStr);

      final date = DateTime.parse(dateStr);
      final weekIndex = ((date.day - 1) ~/ 7).clamp(0, 4);

      if (row['time_in'] != null) {
        hadirCount++;
        totalWork += (row['work_minutes'] as num?)?.toInt() ?? 0;
        totalLate += (row['late_minutes'] as num?)?.toInt() ?? 0;

        if (row['status_in'] == 'late' ||
            ((row['late_minutes'] as num? ?? 0) > 0)) {
          lateCount++;
        }
        if (row['status_out'] == 'early_check_out') earlyOutCount++;
        if (row['status_out'] == 'forgot_checkout') autoCheckoutCount++;

        // Weekly work
        final w = weekly[weekIndex];
        w['work'] = ((w['work'] as int?) ?? 0) +
            ((row['work_minutes'] as num?)?.toInt() ?? 0);
        w['count'] = ((w['count'] as int?) ?? 0) + 1;
      } else {
        // Record exists but no check-in → absent
        tidakHadirCount++;
      }
    }

    // Count absent weekdays with no record
    final today = DateTime.now();
    for (int d = 1; d <= daysInMonth; d++) {
      final day = DateTime(year, month, d);
      if (day.isAfter(today)) break;
      if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
        continue;
      }
      final dateStr = DateFormat('yyyy-MM-dd').format(day);
      if (!recordDates.contains(dateStr)) {
        tidakHadirCount++;
      }
    }

    return {
      'workdays': workdays,
      'hadir': hadirCount,
      'tidak_hadir': tidakHadirCount,
      'work_minutes': totalWork,
      'late_minutes': totalLate,
      'late_count': lateCount,
      'early_out_count': earlyOutCount,
      'auto_checkout_count': autoCheckoutCount,
      'weekly': weekly,
    };
  },
);

// ── Screen ───────────────────────────────────────────────────────────────────

class RingkasanScreen extends ConsumerStatefulWidget {
  const RingkasanScreen({super.key});

  @override
  ConsumerState<RingkasanScreen> createState() => _RingkasanScreenState();
}

class _RingkasanScreenState extends ConsumerState<RingkasanScreen> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _year == now.year && _month == now.month;
  }

  void _prev() => setState(() {
        if (_month == 1) {
          _month = 12;
          _year--;
        } else {
          _month--;
        }
      });

  void _next() {
    if (_isCurrentMonth) return;
    setState(() {
      if (_month == 12) {
        _month = 1;
        _year++;
      } else {
        _month++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Ringkasan'),
      ),
      body: SafeArea(
        top: false,
        child: employeeAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.danger))),
          data: (employee) {
            if (employee == null) {
              return const Center(child: Text('Data karyawan tidak ditemukan'));
            }
            return _buildBody(employee.id);
          },
        ),
      ),
    );
  }

  Widget _buildBody(String employeeId) {
    final summaryAsync =
        ref.watch(_ringkasanProvider((employeeId, _year, _month)));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async =>
          ref.invalidate(_ringkasanProvider((employeeId, _year, _month))),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SizedBox(height: 12),

          // Month selector
          _MonthSelector(
            year: _year,
            month: _month,
            isCurrentMonth: _isCurrentMonth,
            onPrev: _prev,
            onNext: _next,
          ),

          const SizedBox(height: 16),

          summaryAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                  child:
                      CircularProgressIndicator(color: AppColors.primary)),
            ),
            error: (e, _) => Center(
                child: Text('Gagal memuat: $e',
                    style: const TextStyle(color: AppColors.danger))),
            data: (s) => _buildSummary(s),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(Map<String, dynamic> s) {
    final workdays = s['workdays'] as int;
    final hadir = s['hadir'] as int;
    final tidakHadir = s['tidak_hadir'] as int;
    final workMin = s['work_minutes'] as int;
    final lateMin = s['late_minutes'] as int;
    final lateCount = s['late_count'] as int;
    final earlyOut = s['early_out_count'] as int;
    final autoCheckout = s['auto_checkout_count'] as int;

    final hadirPct = workdays > 0 ? (hadir / workdays).clamp(0.0, 1.0) : 0.0;
    final expectedMin = workdays * 8 * 60;
    final workPct =
        expectedMin > 0 ? (workMin / expectedMin).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Kehadiran card ─────────────────────────────────────────────
        _SectionLabel('Kehadiran'),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            children: [
              Row(
                children: [
                  _CircleStat(
                    value: hadir,
                    total: workdays,
                    label: 'Hari Hadir',
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        _StatRow(
                          icon: Icons.check_circle_rounded,
                          color: AppColors.success,
                          label: 'Hadir',
                          value: '$hadir hari',
                        ),
                        const SizedBox(height: 8),
                        _StatRow(
                          icon: Icons.cancel_rounded,
                          color: AppColors.danger,
                          label: 'Tidak Hadir',
                          value: '$tidakHadir hari',
                        ),
                        const SizedBox(height: 8),
                        _StatRow(
                          icon: Icons.computer_rounded,
                          color: const Color(0xFF0E7490),
                          label: 'Auto Checkout',
                          value: '$autoCheckout hari',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ProgressBar(
                  value: hadirPct,
                  color: AppColors.primary,
                  label:
                      '${(hadirPct * 100).toStringAsFixed(0)}% dari $workdays hari kerja'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Jam Kerja card ─────────────────────────────────────────────
        _SectionLabel('Jam Kerja'),
        const SizedBox(height: 8),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fmtDuration(workMin),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'dari ${_fmtDuration(expectedMin)} target',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  Text(
                    '${(workPct * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ProgressBar(
                  value: workPct,
                  color: AppColors.primary,
                  label: null),
              const SizedBox(height: 12),
              _WeeklyChart(weekly: s['weekly'] as List),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Keterlambatan & Keluar Awal ────────────────────────────────
        _SectionLabel('Disiplin'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SmallIcon(
                        icon: Icons.timer_off_rounded,
                        color: Color(0xFFB45309)),
                    const SizedBox(height: 8),
                    Text(
                      '$lateCount',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB45309),
                      ),
                    ),
                    const Text('Hari Terlambat',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      _fmtDuration(lateMin),
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SmallIcon(
                        icon: Icons.exit_to_app_rounded,
                        color: AppColors.danger),
                    const SizedBox(height: 8),
                    Text(
                      '$earlyOut',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.danger,
                      ),
                    ),
                    const Text('Keluar Lebih Awal',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    const Text(' ',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fmtDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}j';
    return '${h}j ${m}m';
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _MonthSelector extends StatelessWidget {
  final int year;
  final int month;
  final bool isCurrentMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _MonthSelector({
    required this.year,
    required this.month,
    required this.isCurrentMonth,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded,
                color: AppColors.primary),
            onPressed: onPrev,
          ),
          Text(
            DateFormat('MMMM yyyy', 'id_ID').format(DateTime(year, month)),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right_rounded,
                color: isCurrentMonth
                    ? AppColors.textMuted
                    : AppColors.primary),
            onPressed: isCurrentMonth ? null : onNext,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary));
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000),
              blurRadius: 12,
              offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

class _CircleStat extends StatelessWidget {
  final int value;
  final int total;
  final String label;
  final Color color;

  const _CircleStat({
    required this.value,
    required this.total,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? value / total : 0.0;
    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 90,
            height: 90,
            child: CircularProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              strokeWidth: 7,
              backgroundColor: color.withValues(alpha: 0.12),
              color: color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$value',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 9, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ),
        Text(value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color)),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final String? label;

  const _ProgressBar({required this.value, required this.color, this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.12),
            color: color,
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(label!,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textMuted)),
        ],
      ],
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  final List weekly;
  const _WeeklyChart({required this.weekly});

  @override
  Widget build(BuildContext context) {
    final maxWork = weekly
        .map((w) => (w as Map<String, dynamic>)['work'] as int? ?? 0)
        .fold(0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Per Minggu',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(weekly.length, (i) {
            final w = weekly[i] as Map<String, dynamic>;
            final work = w['work'] as int? ?? 0;
            final barH = maxWork > 0 ? (work / maxWork) * 60.0 : 0.0;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  children: [
                    Text(
                      work > 0
                          ? '${(work / 60).toStringAsFixed(0)}j'
                          : '',
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: barH > 0 ? barH : 4,
                      decoration: BoxDecoration(
                        color: work > 0
                            ? AppColors.primary
                            : AppColors.textMuted.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('M${i + 1}',
                        style: const TextStyle(
                            fontSize: 9, color: AppColors.textMuted)),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SmallIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _SmallIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
