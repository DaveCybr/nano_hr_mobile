import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/home_provider.dart';
import '../../../shared/models/attendance_model.dart';
import '../../../shared/models/employee_model.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: employeeAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => const Center(
          child: Text(
            'Mohon maaf, terjadi kendala.',
            style: TextStyle(color: AppColors.danger),
          ),
        ),
        data: (employee) {
          if (employee == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.person_off_rounded,
                    color: AppColors.textMuted,
                    size: 56,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Data karyawan tidak ditemukan',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => ref.invalidate(currentEmployeeProvider),
                    child: const Text(
                      'Coba Lagi',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            );
          }

          final todayAttAsync = ref.watch(todayAttendanceProvider(employee.id));
          final scheduleAsync = ref.watch(todayScheduleProvider(employee.id));
          final summaryAsync = ref.watch(monthlySummaryProvider(employee.id));
          final recentAsync = ref.watch(recentAttendancesProvider(employee.id));

          return RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.surfaceContainerLowest,
            onRefresh: () async {
              ref.invalidate(currentEmployeeProvider);
              ref.invalidate(todayAttendanceProvider(employee.id));
              ref.invalidate(todayScheduleProvider(employee.id));
              ref.invalidate(monthlySummaryProvider(employee.id));
              ref.invalidate(recentAttendancesProvider(employee.id));
            },
            child: CustomScrollView(
              slivers: [
                // ── Header ─────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _Header(
                    employee: employee,
                    attendance: todayAttAsync.valueOrNull,
                  ),
                ),

                // ── Today attendance card ─────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _TodayCard(
                      attendance: todayAttAsync.valueOrNull,
                      workIn: scheduleAsync.valueOrNull?['work_in'],
                      workOut: scheduleAsync.valueOrNull?['work_out'],
                      loading: todayAttAsync.isLoading,
                    ),
                  ),
                ),

                // ── Menu grid ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: const _MenuGrid(),
                  ),
                ),

                // ── Kehadiran (recent) ────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Kehadiran',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => context.push('/attendance/history'),
                              child: const Text(
                                'Lihat Semua',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        recentAsync.when(
                          loading: () => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                          error: (_, __) => const Text(
                            'Gagal memuat data',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          data: (list) => _RecentList(list: list),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Ringkasan ─────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Ringkasan',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.onSurface,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => context.push('/ringkasan'),
                              child: const Text(
                                'Lihat Semua',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Daily progress
                        const Text(
                          'Progres Harian',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        todayAttAsync.when(
                          loading: () => const _CardShimmer(),
                          error: (_, __) => const SizedBox(),
                          data: (today) => _DailySummaryCard(
                            today: today,
                            schedule: scheduleAsync.valueOrNull,
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Monthly report
                        Builder(
                          builder: (context) {
                            final now = DateTime.now();
                            final first = DateTime(now.year, now.month, 1);
                            final last = DateTime(now.year, now.month + 1, 0);
                            final range =
                                '${DateFormat('d MMM yyyy', 'id_ID').format(first)} – '
                                '${DateFormat('d MMM yyyy', 'id_ID').format(last)}';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Laporan Bulanan',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  range,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                summaryAsync.when(
                                  loading: () => const _CardShimmer(),
                                  error: (_, __) => const Text(
                                    'Gagal memuat data',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  data: (s) => _MonthlySummaryCard(summary: s),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final EmployeeModel employee;
  final AttendanceModel? attendance;

  const _Header({required this.employee, this.attendance});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Selamat Pagi';
    if (hour < 15) return 'Selamat Siang';
    if (hour < 18) return 'Selamat Sore';
    return 'Selamat Malam';
  }

  @override
  Widget build(BuildContext context) {
    final position = employee.position;
    final positionName = position?['name'] as String? ?? '';
    final roleLabel = _roleLabel(employee.accessType);

    return SafeArea(
      bottom: false,
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Name & greeting
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greeting(),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    employee.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (positionName.isNotEmpty)
                    Text(
                      positionName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    )
                  else
                    Text(
                      roleLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Avatar
            GestureDetector(
              onTap: () => context.push('/account'),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainerLow,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: employee.facePhotoUrl != null
                      ? Image.network(
                          employee.facePhotoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person_rounded,
                            color: AppColors.textMuted,
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          color: AppColors.textMuted,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String accessType) {
    switch (accessType) {
      case 'admin':
        return 'Admin';
      case 'manager':
        return 'Manajer';
      default:
        return 'Pegawai';
    }
  }
}

// ── Schedule Card ────────────────────────────────────────────────────────────

class _TodayCard extends StatelessWidget {
  final AttendanceModel? attendance;
  final String? workIn;
  final String? workOut;
  final bool loading;

  const _TodayCard({
    this.attendance,
    this.workIn,
    this.workOut,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat("'Hari Ini' • d MMM yyyy", 'id_ID').format(now);
    final hasTime = workIn != null && workOut != null;
    // Strip seconds from schedule display (e.g. "09:00:00" → "09:00")
    String _trim(String t) => t.length >= 5 ? t.substring(0, 5) : t;
    final scheduleStr =
        hasTime ? '${_trim(workIn!)} - ${_trim(workOut!)} WIB' : 'Tidak ada jadwal';

    final hasIn = attendance?.hasCheckedIn ?? false;
    final hasOut = attendance?.hasCheckedOut ?? false;

    final timeIn = hasIn && attendance?.timeIn != null
        ? DateFormat('HH:mm:ss').format(DateTime.parse(attendance!.timeIn!).toLocal())
        : '--:--';
    final timeOut = hasOut && attendance?.timeOut != null
        ? DateFormat('HH:mm:ss').format(DateTime.parse(attendance!.timeOut!).toLocal())
        : '--:--';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // ── Header row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => context.push('/attendance/history'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          scheduleStr,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded,
                            size: 14, color: AppColors.primary.withValues(alpha: 0.7)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          Divider(height: 1, thickness: 1, color: AppColors.textMuted.withValues(alpha: 0.08)),

          // ── Check-in / Check-out row ─────────────────────────────────
          loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Row(
                    children: [
                      // CHECK IN
                      Expanded(
                        child: GestureDetector(
                          onTap: hasIn ? null : () => context.push('/checkin/location'),
                          child: _AttCol(
                            label: 'CHECK IN',
                            time: timeIn,
                            hasAction: !hasIn,
                            isDone: hasIn,
                            timeColor: hasIn ? const Color(0xFFDC2626) : AppColors.textMuted,
                            actionColor: AppColors.primary,
                            photoUrl: attendance?.photoInUrl,
                            fallbackIcon: Icons.login_rounded,
                            fallbackIconColor: hasIn ? AppColors.primary : AppColors.textMuted,
                            fallbackIconBg: hasIn
                                ? AppColors.primary.withValues(alpha: 0.10)
                                : AppColors.surfaceContainerLow,
                          ),
                        ),
                      ),
                      // Divider
                      Container(
                        width: 1,
                        height: 44,
                        color: AppColors.textMuted.withValues(alpha: 0.12),
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      // CHECK OUT
                      Expanded(
                        child: GestureDetector(
                          onTap: (hasIn && !hasOut)
                              ? () => context.push('/checkout/location')
                              : null,
                          child: _AttCol(
                            label: 'CHECK OUT',
                            time: timeOut,
                            hasAction: hasIn && !hasOut,
                            isDone: hasOut,
                            timeColor: hasOut ? AppColors.onSurface : AppColors.textMuted,
                            actionColor: const Color(0xFFF97316),
                            fallbackIcon: Icons.logout_rounded,
                            fallbackIconColor:
                                hasOut ? const Color(0xFFF97316) : AppColors.textMuted,
                            fallbackIconBg: hasOut
                                ? const Color(0xFFF97316).withValues(alpha: 0.10)
                                : AppColors.surfaceContainerLow,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

class _AttCol extends StatelessWidget {
  final String label;
  final String time;
  final bool hasAction;
  final bool isDone;
  final Color timeColor;
  final Color actionColor;
  final String? photoUrl;
  final IconData fallbackIcon;
  final Color fallbackIconColor;
  final Color fallbackIconBg;

  const _AttCol({
    required this.label,
    required this.time,
    required this.hasAction,
    required this.isDone,
    required this.timeColor,
    required this.actionColor,
    required this.fallbackIcon,
    required this.fallbackIconColor,
    required this.fallbackIconBg,
    this.photoUrl,
  });

  Widget _avatar() {
    if (photoUrl != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _iconAvatar(),
          placeholder: (_, __) => _iconAvatar(),
        ),
      );
    }
    return _iconAvatar();
  }

  Widget _iconAvatar() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fallbackIconBg),
      child: Icon(fallbackIcon, size: 18, color: fallbackIconColor),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _avatar(),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: timeColor,
                ),
              ),
              Text(
                'WIB',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.textMuted.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone
                ? AppColors.primary.withValues(alpha: 0.12)
                : hasAction
                    ? actionColor.withValues(alpha: 0.12)
                    : AppColors.surfaceContainerLow,
          ),
          child: Icon(
            isDone
                ? Icons.check_rounded
                : hasAction
                    ? Icons.chevron_right_rounded
                    : Icons.remove_rounded,
            size: 14,
            color: isDone
                ? AppColors.primary
                : hasAction
                    ? actionColor
                    : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Menu Grid ────────────────────────────────────────────────────────────────

class _MenuGrid extends StatelessWidget {
  static const _menus = [
    _MenuItem(
      Icons.access_time_rounded,
      'Kehadiran',
      '/attendance/history',
      Color(0xFF006036),
    ),
    _MenuItem(Icons.bar_chart_rounded, 'Aktivitas', '/attendance/history', Color(0xFF1976D2)),
    _MenuItem(Icons.beach_access_rounded, 'Cuti', '/leave', Color(0xFFF57C00)),
    _MenuItem(
      Icons.assignment_rounded,
      'Daftar Tugas',
      null,
      Color(0xFF7B1FA2),
    ),
    _MenuItem(
      Icons.hourglass_bottom_rounded,
      'Lembur',
      '/overtime',
      Color(0xFFF9A825),
    ),
    _MenuItem(Icons.receipt_long_rounded, 'Klaim', null, Color(0xFF00796B)),
    _MenuItem(
      Icons.card_giftcard_rounded,
      'Fleksi\nBenefit',
      null,
      Color(0xFFC2185B),
    ),
    _MenuItem(Icons.grid_view_rounded, 'Lainnya', null, Color(0xFF37474F)),
  ];

  const _MenuGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.82,
        crossAxisSpacing: 0,
        mainAxisSpacing: 0,
      ),
      itemCount: _menus.length,
      itemBuilder: (context, i) {
        final m = _menus[i];
        return GestureDetector(
          onTap: () {
            if (m.route != null) {
              context.push(m.route!);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${m.label} segera hadir'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              );
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: m.color.withValues(alpha: 0.12),
                ),
                child: Icon(m.icon, color: m.color, size: 24),
              ),
              const SizedBox(height: 7),
              Text(
                m.label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String? route;
  final Color color;

  const _MenuItem(this.icon, this.label, this.route, this.color);
}

// ── Recent Attendance List ───────────────────────────────────────────────────

class _RecentList extends StatelessWidget {
  final List<AttendanceModel> list;

  const _RecentList({required this.list});

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'Belum ada data kehadiran',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: list.take(3).map((att) => _RecentItem(att: att)).toList(),
    );
  }
}

class _RecentItem extends StatelessWidget {
  final AttendanceModel att;

  const _RecentItem({required this.att});

  String _workDuration(int minutes) {
    if (minutes <= 0) return '';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m Menit';
    if (m == 0) return '$h Jam';
    return '$h Jam $m Menit';
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(att.attendanceDate);
    final today = DateTime.now();
    final yesterday = DateTime(today.year, today.month, today.day - 1);

    String dateLabel;
    if (date != null) {
      final d = DateTime(date.year, date.month, date.day);
      if (d == DateTime(yesterday.year, yesterday.month, yesterday.day)) {
        dateLabel = 'Kemarin (${DateFormat('d MMMM yyyy', 'id_ID').format(date)})';
      } else {
        dateLabel = DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date);
      }
    } else {
      dateLabel = att.attendanceDate;
    }

    final hasIn = att.hasCheckedIn;
    final hasOut = att.hasCheckedOut;
    final isAutoCheckout = att.statusOut == 'forgot_checkout';

    final timeInStr = hasIn && att.timeIn != null
        ? DateFormat('HH:mm:ss').format(DateTime.parse(att.timeIn!).toLocal())
        : '-';
    final timeOutStr = hasOut && att.timeOut != null
        ? DateFormat('HH:mm:ss').format(DateTime.parse(att.timeOut!).toLocal())
        : '-';

    // Badge
    late String badgeLabel;
    late Color badgeText;
    late Color badgeBg;
    if (isAutoCheckout) {
      badgeLabel = 'Dari Sistem';
      badgeText = const Color(0xFF0E7490);
      badgeBg = const Color(0xFFCFFAFE);
    } else if (hasIn) {
      if (att.statusIn == 'late') {
        badgeLabel = 'Terlambat';
        badgeText = const Color(0xFFB45309);
        badgeBg = const Color(0xFFFEF3C7);
      } else {
        badgeLabel = 'Hadir';
        badgeText = const Color(0xFF166534);
        badgeBg = const Color(0xFFDCFCE7);
      }
    } else {
      badgeLabel = 'Absen';
      badgeText = AppColors.danger;
      badgeBg = AppColors.errorContainer;
    }

    final workDuration = hasOut ? _workDuration(att.workMinutes) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: isAutoCheckout
            ? Border.all(
                color: const Color(0xFF0E7490).withValues(alpha: 0.3),
                width: 1,
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: date + badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    if (workDuration.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        workDuration,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    color: badgeText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          if (!hasIn) ...[
            const SizedBox(height: 8),
            Text(
              att.reasonIn?.isNotEmpty == true ? att.reasonIn! : 'Tanpa keterangan',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Row(
              children: [
                // Check In
                Expanded(
                  child: _TimeColumn(
                    label: 'CHECK IN',
                    time: timeInStr,
                    isSystem: false,
                    timeColor: isAutoCheckout
                        ? const Color(0xFFDC2626)
                        : AppColors.onSurface,
                    photoUrl: att.photoInUrl,
                  ),
                ),
                // Divider
                Container(
                  width: 1,
                  height: 40,
                  color: AppColors.textSecondary.withValues(alpha: 0.15),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                // Check Out
                Expanded(
                  child: _TimeColumn(
                    label: 'CHECK OUT',
                    time: timeOutStr,
                    isSystem: isAutoCheckout,
                    timeColor: isAutoCheckout
                        ? const Color(0xFF0E7490)
                        : AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  final String label;
  final String time;
  final bool isSystem;
  final Color timeColor;
  final String? photoUrl;

  const _TimeColumn({
    required this.label,
    required this.time,
    required this.isSystem,
    required this.timeColor,
    this.photoUrl,
  });

  Widget _fallbackAvatar() {
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

  @override
  Widget build(BuildContext context) {
    Widget avatar;
    if (photoUrl != null) {
      avatar = ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _fallbackAvatar(),
          placeholder: (_, __) => _fallbackAvatar(),
        ),
      );
    } else {
      avatar = _fallbackAvatar();
    }

    return Row(
      children: [
        avatar,
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              time,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: timeColor,
              ),
            ),
            Text(
              'WIB',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Card shimmer (loading placeholder) ──────────────────────────────────────

class _CardShimmer extends StatelessWidget {
  const _CardShimmer();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

// ── Daily Summary Card ────────────────────────────────────────────────────────

class _DailySummaryCard extends StatefulWidget {
  final AttendanceModel? today;
  final Map<String, String?>? schedule;

  const _DailySummaryCard({this.today, this.schedule});

  @override
  State<_DailySummaryCard> createState() => _DailySummaryCardState();
}

class _DailySummaryCardState extends State<_DailySummaryCard> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(_DailySummaryCard old) {
    super.didUpdateWidget(old);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    // Only tick when checked in but not yet checked out
    if (widget.today?.hasCheckedIn == true && widget.today?.hasCheckedOut == false) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int _elapsedSeconds() {
    final today = widget.today;
    if (today == null || !today.hasCheckedIn) return 0;
    if (today.hasCheckedOut) return (today.workMinutes) * 60;
    final timeIn = DateTime.tryParse(today.timeIn!)?.toLocal();
    if (timeIn == null) return 0;
    return _now.difference(timeIn).inSeconds.clamp(0, 999999);
  }

  String _fmt(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '$h jam  -  $m menit  -  $s detik';
  }

  String _fmtMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '$h jam  -  $m menit  -  0 detik';
  }

  double _progress(int totalSeconds) {
    final inStr = widget.schedule?['work_in'];
    final outStr = widget.schedule?['work_out'];
    if (inStr == null || outStr == null) return 0;
    final inP = inStr.split(':');
    final outP = outStr.split(':');
    final scheduledSeconds =
        ((int.parse(outP[0]) * 60 + int.parse(outP[1])) -
         (int.parse(inP[0]) * 60 + int.parse(inP[1]))) * 60;
    if (scheduledSeconds <= 0) return 0;
    return (totalSeconds / scheduledSeconds).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final lateMin = widget.today?.lateMinutes ?? 0;
    final elapsedSec = _elapsedSeconds();
    final progress = _progress(elapsedSec);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _SummaryRowItem(
            label: 'Jam Kerja',
            icon: Icons.access_time_rounded,
            color: AppColors.primary,
            value: _fmt(elapsedSec),
            progress: progress,
            isLast: false,
          ),
          _SummaryRowItem(
            label: 'Total Jam Telat',
            icon: Icons.timer_off_rounded,
            color: AppColors.danger,
            value: _fmtMinutes(lateMin),
            isLast: false,
          ),
        ],
      ),
    );
  }
}

// ── Monthly Summary Card ──────────────────────────────────────────────────────

class _MonthlySummaryCard extends StatelessWidget {
  final Map<String, dynamic> summary;

  const _MonthlySummaryCard({required this.summary});

  String _fmt(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '$h jam  -  $m menit  -  0 detik';
  }

  @override
  Widget build(BuildContext context) {
    final workMin = summary['work_minutes'] as int? ?? 0;
    final lateMin = summary['late_minutes'] as int? ?? 0;
    final earlyCount = summary['early_out_count'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _SummaryRowItem(
            label: 'Jam Kerja',
            icon: Icons.access_time_rounded,
            color: AppColors.primary,
            value: _fmt(workMin),
            isLast: false,
          ),
          _SummaryRowItem(
            label: 'Total Jam Telat',
            icon: Icons.timer_off_rounded,
            color: AppColors.danger,
            value: _fmt(lateMin),
            isLast: false,
          ),
          _SummaryRowItem(
            label: 'Keluar Lebih Awal',
            icon: Icons.exit_to_app_rounded,
            color: AppColors.warning,
            value: '$earlyCount kali',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

// ── Summary Row Item ──────────────────────────────────────────────────────────

class _SummaryRowItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String value;
  final double? progress;
  final bool isLast;

  const _SummaryRowItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
    this.progress,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chip label
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Icon(icon, color: color, size: 12),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Progress bar (only for jam kerja)
        if (progress != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.surfaceContainerLow,
                    color: color,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${((progress ?? 0) * 100).toStringAsFixed(0)} %',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],

        // Value
        const SizedBox(height: 6),
        Row(
          children: [
            // Icon(icon, color: color, size: 15),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),

        if (!isLast) ...[
          const SizedBox(height: 12),
          const Divider(color: AppColors.surfaceContainerLow, height: 1),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
