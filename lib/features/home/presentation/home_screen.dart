import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../providers/home_provider.dart';
import '../../../shared/models/attendance_model.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _navIndex = 0;

  Future<void> _refresh() async {
    ref.invalidate(currentEmployeeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      body: employeeAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: AppColors.danger))),
        data: (employee) {
          if (employee == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_off,
                      color: AppColors.textMuted, size: 64),
                  const SizedBox(height: 16),
                  const Text('Data karyawan tidak ditemukan',
                      style: AppTextStyles.bodySecondary),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('Coba Lagi',
                        style: TextStyle(color: AppColors.primary)),
                  ),
                ],
              ),
            );
          }

          final todayAttendanceAsync =
              ref.watch(todayAttendanceProvider(employee.id));
          final scheduleParams = {
            'employee_id': employee.id,
            'group': employee.group,
          };
          final scheduleAsync = ref.watch(todayScheduleProvider(scheduleParams));
          final summaryAsync = ref.watch(monthlySummaryProvider(employee.id));
          final recentAsync =
              ref.watch(recentAttendancesProvider(employee.id));

          return RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.bgCard,
            onRefresh: () async {
              ref.invalidate(currentEmployeeProvider);
              ref.invalidate(todayAttendanceProvider(employee.id));
              ref.invalidate(todayScheduleProvider(scheduleParams));
              ref.invalidate(monthlySummaryProvider(employee.id));
              ref.invalidate(recentAttendancesProvider(employee.id));
            },
            child: CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: _buildHeader(context, employee, todayAttendanceAsync.valueOrNull),
                ),
                // Schedule card
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: scheduleAsync.when(
                      loading: () => _buildScheduleCardLoading(),
                      error: (_, __) => _buildScheduleCardEmpty(),
                      data: (schedule) => _buildScheduleCard(schedule),
                    ),
                  ),
                ),
                // Check-in / Check-out cards
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: todayAttendanceAsync.when(
                      loading: () => const SizedBox(
                          height: 120,
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary))),
                      error: (_, __) => const SizedBox(),
                      data: (attendance) => _buildAttendanceCards(
                          context, employee.id, attendance,
                          scheduleAsync.valueOrNull),
                    ),
                  ),
                ),
                // Menu grid
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildMenuGrid(context),
                  ),
                ),
                // Recent attendance
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Kehadiran Terkini',
                            style: AppTextStyles.heading3),
                        const SizedBox(height: 12),
                        recentAsync.when(
                          loading: () => const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary)),
                          error: (_, __) => const Text('Gagal memuat data',
                              style: AppTextStyles.bodySecondary),
                          data: (list) => _buildRecentList(list),
                        ),
                      ],
                    ),
                  ),
                ),
                // Monthly summary
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Ringkasan Bulan Ini',
                            style: AppTextStyles.heading3),
                        const SizedBox(height: 12),
                        summaryAsync.when(
                          loading: () => const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary)),
                          error: (_, __) => const Text('Gagal memuat data',
                              style: AppTextStyles.bodySecondary),
                          data: (summary) => _buildMonthlySummary(summary),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNav(context),
      floatingActionButton: _buildFAB(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildHeader(BuildContext context, employee, AttendanceModel? attendance) {
    final group = employee.group as Map<String, dynamic>?;
    final position = employee.position as Map<String, dynamic>?;
    final groupName = group?['name'] as String? ?? 'nano.HR';
    final positionName = position?['name'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(groupName,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  employee.fullName.toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
                if (positionName.isNotEmpty)
                  Text(positionName, style: AppTextStyles.bodySecondary),
              ],
            ),
          ),
          // Avatar
          GestureDetector(
            onTap: () => context.push('/account'),
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 2),
                color: AppColors.bgPrimary,
              ),
              child: ClipOval(
                child: employee.facePhotoUrl != null
                    ? Image.network(
                        employee.facePhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.person,
                            color: AppColors.textSecondary),
                      )
                    : const Icon(Icons.person, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(Map<String, String?> schedule) {
    final now = DateTime.now();
    final dayNames = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
    final dayStr = dayNames[now.weekday % 7];
    final dateStr = DateFormat('d MMMM yyyy', 'id_ID').format(now);
    final workIn = schedule['work_in'] ?? '-';
    final workOut = schedule['work_out'] ?? '-';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: AppColors.primary, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$dayStr, $dateStr',
                    style: AppTextStyles.body
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Jadwal: $workIn – $workOut',
                    style: AppTextStyles.bodySecondary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCardLoading() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Memuat jadwal...', style: AppTextStyles.bodySecondary),
        ],
      ),
    );
  }

  Widget _buildScheduleCardEmpty() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: AppColors.textMuted, size: 18),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(DateTime.now()),
                style: AppTextStyles.body,
              ),
              const Text('Tidak ada jadwal', style: AppTextStyles.bodySecondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCards(BuildContext context, String employeeId,
      AttendanceModel? attendance, Map<String, String?>? schedule) {
    final hasCheckedIn = attendance?.hasCheckedIn ?? false;
    final hasCheckedOut = attendance?.hasCheckedOut ?? false;

    String? timeInStr;
    String? timeOutStr;
    if (hasCheckedIn && attendance?.timeIn != null) {
      final dt = DateTime.parse(attendance!.timeIn!).toLocal();
      timeInStr = DateFormat('HH:mm').format(dt);
    }
    if (hasCheckedOut && attendance?.timeOut != null) {
      final dt = DateTime.parse(attendance!.timeOut!).toLocal();
      timeOutStr = DateFormat('HH:mm').format(dt);
    }

    return Row(
      children: [
        // Check-in card
        Expanded(
          child: GestureDetector(
            onTap: hasCheckedIn
                ? null
                : () => context.push('/checkin/location'),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hasCheckedIn
                    ? AppColors.success.withValues(alpha: 0.15)
                    : AppColors.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasCheckedIn
                      ? AppColors.success.withValues(alpha: 0.5)
                      : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasCheckedIn
                            ? Icons.check_circle
                            : Icons.login,
                        color: hasCheckedIn
                            ? AppColors.success
                            : AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text('CHECK IN',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (hasCheckedIn)
                    Text(timeInStr ?? '--:--',
                        style: const TextStyle(
                            color: AppColors.success,
                            fontSize: 22,
                            fontWeight: FontWeight.bold))
                  else
                    const Text('Belum',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 16,
                            fontWeight: FontWeight.w500)),
                  if (attendance?.statusIn != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _buildStatusBadge(attendance!.statusIn!),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Check-out card
        Expanded(
          child: GestureDetector(
            onTap: (hasCheckedIn && !hasCheckedOut)
                ? () => context.push('/checkout/location')
                : null,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hasCheckedOut
                    ? AppColors.orange.withValues(alpha: 0.15)
                    : (hasCheckedIn && !hasCheckedOut)
                        ? AppColors.bgCardLight
                        : AppColors.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasCheckedOut
                      ? AppColors.orange.withValues(alpha: 0.5)
                      : (hasCheckedIn && !hasCheckedOut)
                          ? AppColors.orange.withValues(alpha: 0.3)
                          : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasCheckedOut
                            ? Icons.check_circle
                            : Icons.logout,
                        color: hasCheckedOut
                            ? AppColors.orange
                            : (hasCheckedIn && !hasCheckedOut)
                                ? AppColors.orange
                                : AppColors.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text('CHECK OUT',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (hasCheckedOut)
                    Text(timeOutStr ?? '--:--',
                        style: const TextStyle(
                            color: AppColors.orange,
                            fontSize: 22,
                            fontWeight: FontWeight.bold))
                  else
                    Text(
                      hasCheckedIn ? 'Tap untuk out' : 'Belum',
                      style: TextStyle(
                          color: hasCheckedIn
                              ? AppColors.orange
                              : AppColors.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                  if (attendance?.statusOut != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _buildStatusBadge(attendance!.statusOut!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'on_time':
        color = AppColors.success;
        label = 'Tepat Waktu';
        break;
      case 'in_tolerance':
        color = AppColors.warning;
        label = 'Toleransi';
        break;
      case 'late':
        color = AppColors.danger;
        label = 'Terlambat';
        break;
      case 'early_check_out':
        color = AppColors.warning;
        label = 'Lebih Awal';
        break;
      default:
        color = AppColors.textMuted;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildMenuGrid(BuildContext context) {
    final menus = [
      {'icon': Icons.history, 'label': 'Kehadiran', 'route': '/attendance/history'},
      {'icon': Icons.bar_chart, 'label': 'Aktivitas', 'route': null},
      {'icon': Icons.beach_access, 'label': 'Cuti', 'route': '/leave'},
      {'icon': Icons.assignment, 'label': 'Daftar Tugas', 'route': null},
      {'icon': Icons.more_time, 'label': 'Lembur', 'route': '/overtime'},
      {'icon': Icons.receipt_long, 'label': 'Klaim', 'route': null},
      {'icon': Icons.auto_awesome, 'label': 'Fleksi Benefit', 'route': null},
      {'icon': Icons.more_horiz, 'label': 'Lainnya', 'route': null},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.85,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: menus.length,
      itemBuilder: (context, i) {
        final menu = menus[i];
        return GestureDetector(
          onTap: () {
            final route = menu['route'] as String?;
            if (route != null) context.push(route);
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(menu['icon'] as IconData,
                    color: AppColors.primary, size: 24),
                const SizedBox(height: 6),
                Text(
                  menu['label'] as String,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentList(List<AttendanceModel> list) {
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Belum ada data kehadiran',
            style: AppTextStyles.bodySecondary),
      );
    }
    final displayed = list.take(3).toList();
    return Column(
      children: displayed.map((att) => _buildRecentItem(att)).toList(),
    );
  }

  Widget _buildRecentItem(AttendanceModel att) {
    final date = att.attendanceDate;
    DateTime? dt;
    try {
      dt = DateTime.parse(date);
    } catch (_) {}

    final dayStr = dt != null
        ? DateFormat('EEE, d MMM', 'id_ID').format(dt)
        : date;

    final hasIn = att.hasCheckedIn;
    final timeIn = hasIn && att.timeIn != null
        ? DateFormat('HH:mm').format(DateTime.parse(att.timeIn!).toLocal())
        : '-';
    final timeOut = att.hasCheckedOut && att.timeOut != null
        ? DateFormat('HH:mm').format(DateTime.parse(att.timeOut!).toLocal())
        : '-';

    Color badgeColor;
    String badgeLabel;
    if (hasIn) {
      if (att.statusIn == 'late') {
        badgeColor = AppColors.badgeTerlambat;
        badgeLabel = 'Terlambat';
      } else {
        badgeColor = AppColors.badgeHadir;
        badgeLabel = 'Hadir';
      }
    } else {
      badgeColor = AppColors.badgeTidakHadir;
      badgeLabel = 'Tidak Hadir';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dayStr, style: AppTextStyles.body),
                const SizedBox(height: 2),
                Text('Masuk: $timeIn  •  Keluar: $timeOut',
                    style: AppTextStyles.bodySecondary),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(badgeLabel,
                style: TextStyle(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlySummary(Map<String, dynamic> summary) {
    final workMin = summary['work_minutes'] as int? ?? 0;
    final lateMin = summary['late_minutes'] as int? ?? 0;
    final earlyMin = summary['early_out_minutes'] as int? ?? 0;

    String fmtMinutes(int m) {
      final h = m ~/ 60;
      final min = m % 60;
      return '${h}j ${min}m';
    }

    return Row(
      children: [
        Expanded(
            child: _buildSummaryTile('Jam Kerja', fmtMinutes(workMin),
                AppColors.primary, Icons.access_time)),
        const SizedBox(width: 8),
        Expanded(
            child: _buildSummaryTile('Total Telat', fmtMinutes(lateMin),
                AppColors.danger, Icons.timer_off)),
        const SizedBox(width: 8),
        Expanded(
            child: _buildSummaryTile('Keluar Awal', fmtMinutes(earlyMin),
                AppColors.warning, Icons.exit_to_app)),
      ],
    );
  }

  Widget _buildSummaryTile(
      String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return BottomAppBar(
      color: AppColors.bgCard,
      shape: const CircularNotchedRectangle(),
      notchMargin: 6,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(0, Icons.home, 'Beranda', context),
          _navItem(1, Icons.notifications_outlined, 'Notifikasi', context),
          const SizedBox(width: 48),
          _navItem(2, Icons.calendar_month_outlined, 'Jadwal', context),
          _navItem(3, Icons.person_outline, 'Akun', context),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label, BuildContext context) {
    final isActive = _navIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _navIndex = index);
        switch (index) {
          case 1:
            context.push('/notifications');
            break;
          case 2:
            context.push('/schedule');
            break;
          case 3:
            context.push('/account');
            break;
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              color: isActive ? AppColors.primary : AppColors.textMuted,
              size: 22),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: isActive ? AppColors.primary : AppColors.textMuted,
                  fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildFAB(BuildContext context) {
    final employeeAsync = ref.watch(currentEmployeeProvider);
    final employee = employeeAsync.valueOrNull;
    AttendanceModel? attendance;
    if (employee != null) {
      attendance =
          ref.watch(todayAttendanceProvider(employee.id)).valueOrNull;
    }

    final hasCheckedIn = attendance?.hasCheckedIn ?? false;
    final hasCheckedOut = attendance?.hasCheckedOut ?? false;
    final fabColor =
        (hasCheckedIn && !hasCheckedOut) ? AppColors.orange : AppColors.primary;
    final fabIcon = (hasCheckedIn && !hasCheckedOut)
        ? Icons.logout
        : Icons.login;

    return FloatingActionButton(
      backgroundColor: fabColor,
      onPressed: () {
        if (!hasCheckedIn) {
          context.push('/checkin/location');
        } else if (!hasCheckedOut) {
          context.push('/checkout/location');
        }
      },
      child: Icon(fabIcon, color: Colors.white),
    );
  }
}
