import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../providers/home_provider.dart';

class RingkasanScreen extends ConsumerWidget {
  const RingkasanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeeAsync = ref.watch(currentEmployeeProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.bgPrimary,
        title: const Text('Ringkasan'),
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
          return _RingkasanContent(employeeId: employee.id);
        },
      ),
    );
  }
}

class _RingkasanContent extends ConsumerWidget {
  final String employeeId;
  const _RingkasanContent({required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayAttendanceProvider(employeeId));
    final scheduleAsync = ref.watch(todayScheduleProvider(employeeId));
    final summaryAsync = ref.watch(monthlySummaryProvider(employeeId));

    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final monthRange =
        '${DateFormat('d MMMM yyyy', 'id_ID').format(firstDay)} - '
        '${DateFormat('d MMMM yyyy', 'id_ID').format(lastDay)}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Progres Harian ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Progres Harian',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                // Work progress bar
                todayAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2)),
                  error: (_, __) => const SizedBox(),
                  data: (today) {
                    final workMin = today?.workMinutes ?? 0;
                    final lateMin = today?.lateMinutes ?? 0;

                    // Calculate scheduled minutes from schedule
                    double progress = 0;
                    scheduleAsync.whenData((s) {
                      final inStr = s['work_in'];
                      final outStr = s['work_out'];
                      if (inStr != null && outStr != null) {
                        final inParts = inStr.split(':');
                        final outParts = outStr.split(':');
                        final scheduled = (int.parse(outParts[0]) * 60 +
                                int.parse(outParts[1])) -
                            (int.parse(inParts[0]) * 60 +
                                int.parse(inParts[1]));
                        if (scheduled > 0) {
                          progress = (workMin / scheduled).clamp(0.0, 1.0);
                        }
                      }
                    });

                    return Column(children: [
                      _summaryRow('Jam Kerja', workMin, AppColors.primary,
                          Icons.access_time_rounded,
                          showBar: true, progress: progress),
                      const Divider(color: AppColors.border, height: 20),
                      _summaryRow('Total Jam Telat', lateMin, AppColors.danger,
                          Icons.timer_off_rounded),
                      const Divider(color: AppColors.border, height: 20),
                      _summaryRow('Keluar Lebih Awal', 0, AppColors.warning,
                          Icons.exit_to_app_rounded),
                    ]);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Laporan Bulanan ─────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Laporan Bulanan',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(monthRange, style: AppTextStyles.caption),
                const SizedBox(height: 14),
                summaryAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2)),
                  error: (_, __) => const Text('Gagal memuat data',
                      style: AppTextStyles.bodySecondary),
                  data: (s) {
                    final workMin = s['work_minutes'] as int? ?? 0;
                    final lateMin = s['late_minutes'] as int? ?? 0;
                    final earlyMin = s['early_out_minutes'] as int? ?? 0;
                    return Column(children: [
                      _summaryRow('Jam Kerja', workMin, AppColors.primary,
                          Icons.access_time_rounded),
                      const Divider(color: AppColors.border, height: 20),
                      _summaryRow('Total Jam Telat', lateMin, AppColors.danger,
                          Icons.timer_off_rounded),
                      const Divider(color: AppColors.border, height: 20),
                      _summaryRow('Keluar Lebih Awal', earlyMin,
                          AppColors.warning, Icons.exit_to_app_rounded),
                    ]);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    int minutes,
    Color color,
    IconData icon, {
    bool showBar = false,
    double progress = 0,
  }) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    const s = 0; // seconds not tracked at summary level

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        if (showBar) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColors.border,
                  color: color,
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('${(progress * 100).toStringAsFixed(0)} %',
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 11)),
          ]),
        ],
        const SizedBox(height: 6),
        Row(children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            '$h jam  -  $m menit  -  $s detik',
            style: TextStyle(color: color, fontSize: 13),
          ),
        ]),
      ],
    );
  }
}
