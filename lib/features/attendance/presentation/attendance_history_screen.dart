import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/models/attendance_model.dart';
import '../../home/providers/home_provider.dart';
import '../../../core/supabase/supabase_client.dart';

final _historyProvider =
    FutureProvider.family<List<AttendanceModel>, (String, int, int)>(
  (ref, params) async {
    final (employeeId, year, month) = params;

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
      body: SafeArea(
        top: false,
        child: employeeAsync.when(
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
      ),
    );
  }

  Widget _buildContent(String employeeId) {
    final historyAsync = ref.watch(_historyProvider((employeeId, _selectedYear, _selectedMonth)));

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
            data: (records) {
              // Generate all days of selected month descending
              final daysInMonth =
                  DateTime(_selectedYear, _selectedMonth + 1, 0).day;
              final today = DateTime.now();
              final days = List.generate(daysInMonth, (i) {
                final d = DateTime(_selectedYear, _selectedMonth, daysInMonth - i);
                // Skip future days
                if (d.isAfter(DateTime(today.year, today.month, today.day))) return null;
                return d;
              }).whereType<DateTime>().toList();

              // Map records by date string
              final recordMap = {
                for (final r in records) r.attendanceDate: r,
              };

              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async {
                  ref.invalidate(_historyProvider(
                      (employeeId, _selectedYear, _selectedMonth)));
                },
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: days.length,
                  itemBuilder: (ctx, i) {
                    final day = days[i];
                    final dateKey =
                        DateFormat('yyyy-MM-dd').format(day);
                    final att = recordMap[dateKey];
                    return _buildDayItem(day, att);
                  },
                ),
              );
            },
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

  Widget _buildDayItem(DateTime day, AttendanceModel? att) {
    final isWeekend = day.weekday == DateTime.sunday || day.weekday == DateTime.saturday;
    final dayLabel = DateFormat('EEEE, d MMM yyyy', 'id_ID').format(day);
    final hasIn = att?.hasCheckedIn ?? false;
    final hasOut = att?.hasCheckedOut ?? false;
    final isAutoCheckout = att?.statusOut == 'forgot_checkout';
    final onlyCheckedIn = hasIn && !hasOut;

    final timeIn = hasIn && att?.timeIn != null
        ? DateFormat('HH:mm:ss').format(DateTime.parse(att!.timeIn!).toLocal())
        : '--:--:--';
    final timeOut = hasOut && att?.timeOut != null
        ? DateFormat('HH:mm:ss').format(DateTime.parse(att!.timeOut!).toLocal())
        : '--:--:--';

    // Badge
    late String badgeLabel;
    late Color badgeColor;
    if (att == null && isWeekend) {
      badgeLabel = 'Libur';
      badgeColor = const Color(0xFFE91E63);
    } else if (att == null || !hasIn) {
      badgeLabel = 'Tidak Hadir';
      badgeColor = AppColors.danger;
    } else if (isAutoCheckout) {
      badgeLabel = 'Dari Sistem';
      badgeColor = const Color(0xFF0E7490);
    } else if (onlyCheckedIn) {
      badgeLabel = 'Check In';
      badgeColor = AppColors.textMuted;
    } else if (att.statusIn == 'late') {
      badgeLabel = 'Terlambat';
      badgeColor = AppColors.warning;
    } else if (att.statusIn == 'in_tolerance') {
      badgeLabel = 'Toleransi';
      badgeColor = AppColors.primary;
    } else {
      badgeLabel = 'Hadir';
      badgeColor = AppColors.success;
    }

    final workDuration = (att != null && att.workMinutes > 0)
        ? _fmtDuration(att.workMinutes)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dayLabel, style: AppTextStyles.body),
                    if (workDuration != null) ...[
                      const SizedBox(height: 2),
                      Text(workDuration,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
              _badge(badgeLabel, badgeColor),
            ],
          ),

          // Time columns (only if has attendance)
          if (hasIn) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _timeCol(
                    label: 'CHECK IN',
                    time: timeIn,
                    timeColor: const Color(0xFFDC2626),
                    photoUrl: att?.photoInUrl,
                    isSystem: false,
                  ),
                ),
                Container(
                  width: 1,
                  height: 44,
                  color: AppColors.border,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                Expanded(
                  child: _timeCol(
                    label: 'CHECK OUT',
                    time: timeOut,
                    timeColor: hasOut
                        ? AppColors.onSurface
                        : AppColors.textMuted,
                    isSystem: isAutoCheckout,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeCol({
    required String label,
    required String time,
    required Color timeColor,
    required bool isSystem,
    String? photoUrl,
  }) {
    Widget avatar;
    if (photoUrl != null) {
      avatar = ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _iconAvatar(isSystem),
          placeholder: (_, __) => _iconAvatar(isSystem),
        ),
      );
    } else {
      avatar = _iconAvatar(isSystem);
    }

    return Row(
      children: [
        avatar,
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                    letterSpacing: 0.4)),
            const SizedBox(height: 2),
            Text(time,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: timeColor)),
            Text('WIB',
                style: TextStyle(
                    fontSize: 9,
                    color: AppColors.textMuted.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  Widget _iconAvatar(bool isSystem) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSystem
            ? const Color(0xFF0E7490).withValues(alpha: 0.12)
            : AppColors.primary.withValues(alpha: 0.10),
      ),
      child: Icon(
        isSystem ? Icons.computer_rounded : Icons.person_rounded,
        size: 18,
        color: isSystem ? const Color(0xFF0E7490) : AppColors.primary,
      ),
    );
  }

  Widget _badge(String label, Color color) {
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

  String _fmtDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m Menit';
    if (m == 0) return '$h Jam';
    return '$h Jam $m Menit';
  }
}
