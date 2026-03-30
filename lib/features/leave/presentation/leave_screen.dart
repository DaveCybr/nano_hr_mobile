import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../home/providers/home_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _leaveCategoriesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase
      .from('leave_categories')
      .select()
      .order('leave_name');
  return (data as List).cast<Map<String, dynamic>>();
});

final _leaveRequestsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, employeeId) async {
  final data = await supabase
      .from('leave_requests')
      .select('*, leave_category:leave_categories(leave_name, leave_type)')
      .eq('employee_id', employeeId)
      .isFilter('deleted_at', null)
      .order('created_at', ascending: false);
  return (data as List).cast<Map<String, dynamic>>();
});

final _leaveBalancesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, employeeId) async {
  final year = DateTime.now().year;
  final data = await supabase
      .from('leave_balances')
      .select('*, leave_category:leave_categories(leave_name, leave_type, limit_per_year)')
      .eq('employee_id', employeeId)
      .eq('year', year);
  return (data as List).cast<Map<String, dynamic>>();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        title: const Text('Cuti'),
      ),
      floatingActionButton: employeeAsync.valueOrNull == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => LeaveSubmitSheet(
                    employeeId: employeeAsync.value!.id),
              ),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajukan Cuti',
                  style: TextStyle(fontWeight: FontWeight.w600)),
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
            return _LeaveBody(employeeId: employee.id);
          },
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _LeaveBody extends ConsumerWidget {
  final String employeeId;
  const _LeaveBody({required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balancesAsync = ref.watch(_leaveBalancesProvider(employeeId));
    final requestsAsync = ref.watch(_leaveRequestsProvider(employeeId));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(_leaveBalancesProvider(employeeId));
        ref.invalidate(_leaveRequestsProvider(employeeId));
        ref.invalidate(_leaveCategoriesProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          const SizedBox(height: 12),

          // ── Sisa Cuti ─────────────────────────────────────────────
          const _SectionTitle('Sisa Cuti Tahun Ini'),
          const SizedBox(height: 8),
          balancesAsync.when(
            loading: () => const _Shimmer(height: 90),
            error: (_, __) => const SizedBox(),
            data: (balances) => balances.isEmpty
                ? _emptyBalance()
                : Column(
                    children: balances
                        .map((b) => _BalanceCard(balance: b))
                        .toList(),
                  ),
          ),

          const SizedBox(height: 20),

          // ── Riwayat Pengajuan ─────────────────────────────────────
          const _SectionTitle('Riwayat Pengajuan'),
          const SizedBox(height: 8),
          requestsAsync.when(
            loading: () => const _Shimmer(height: 200),
            error: (_, __) => const SizedBox(),
            data: (requests) => requests.isEmpty
                ? _emptyRequests()
                : Column(
                    children: requests
                        .map((r) => _RequestCard(request: r))
                        .toList(),
                  ),
          ),
        ],
      ),
      // ── FAB ───────────────────────────────────────────────────────
      // mounted as floating action button from parent
    );
  }

  Widget _emptyBalance() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text('Belum ada data saldo cuti',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
      );

  Widget _emptyRequests() => Container(
        padding: const EdgeInsets.all(32),
        child: const Column(
          children: [
            Icon(Icons.beach_access_rounded,
                color: AppColors.textMuted, size: 48),
            SizedBox(height: 12),
            Text('Belum ada pengajuan cuti',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
}

// ── Balance Card ──────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final Map<String, dynamic> balance;
  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final category = balance['leave_category'] as Map<String, dynamic>?;
    final name = category?['leave_name'] ?? '-';
    final limit = (category?['limit_per_year'] as num?)?.toInt();
    final taken = ((balance['annual_taken'] as num?)?.toInt() ?? 0) +
        ((balance['other_taken'] as num?)?.toInt() ?? 0);
    final remaining = limit != null ? (limit - taken).clamp(0, limit) : null;
    final pct =
        (limit != null && limit > 0) ? (taken / limit).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface)),
              if (remaining != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: remaining > 0
                        ? AppColors.primary.withValues(alpha: 0.10)
                        : AppColors.danger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$remaining hari tersisa',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: remaining > 0
                            ? AppColors.primary
                            : AppColors.danger),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (limit != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: AppColors.primary.withValues(alpha: 0.10),
                color: pct >= 1.0 ? AppColors.danger : AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text('$taken dari $limit hari terpakai',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

// ── Request Card ──────────────────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final category = request['leave_category'] as Map<String, dynamic>?;
    final name = category?['leave_name'] ?? '-';
    final status = request['status'] as String? ?? 'pending';
    final startDate = DateTime.tryParse(request['start_date'] ?? '');
    final endDate = DateTime.tryParse(request['end_date'] ?? '');
    final totalDays = request['total_days'] as int? ?? 1;
    final reason = request['reason'] as String?;
    final createdAt = DateTime.tryParse(request['created_at'] ?? '');

    final dateRange = (startDate != null && endDate != null)
        ? startDate.isAtSameMomentAs(endDate) ||
                startDate.day == endDate.day &&
                    startDate.month == endDate.month &&
                    startDate.year == endDate.year
            ? DateFormat('d MMM yyyy', 'id_ID').format(startDate)
            : '${DateFormat('d MMM', 'id_ID').format(startDate)} – ${DateFormat('d MMM yyyy', 'id_ID').format(endDate)}'
        : '-';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case 'approved':
        statusColor = AppColors.success;
        statusLabel = 'Disetujui';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'rejected':
        statusColor = AppColors.danger;
        statusLabel = 'Ditolak';
        statusIcon = Icons.cancel_rounded;
        break;
      default:
        statusColor = AppColors.warning;
        statusLabel = 'Menunggu';
        statusIcon = Icons.hourglass_top_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: statusColor, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 11, color: statusColor),
                    const SizedBox(width: 4),
                    Text(statusLabel,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded,
                  size: 13, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(dateRange,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              const Icon(Icons.schedule_rounded,
                  size: 13, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text('$totalDays hari',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted)),
          ],
          if (createdAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Diajukan ${DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(createdAt.toLocal())}',
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Submit Sheet ──────────────────────────────────────────────────────────────

class LeaveSubmitSheet extends ConsumerStatefulWidget {
  final String employeeId;
  const LeaveSubmitSheet({required this.employeeId, super.key});

  @override
  ConsumerState<LeaveSubmitSheet> createState() => _LeaveSubmitSheetState();
}

class _LeaveSubmitSheetState extends ConsumerState<LeaveSubmitSheet> {
  String? _selectedCategoryId;
  DateTime? _startDate;
  DateTime? _endDate;
  final _reasonCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  int get _totalDays {
    if (_startDate == null || _endDate == null) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      locale: const Locale('id', 'ID'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _submit(List<Map<String, dynamic>> categories) async {
    if (_selectedCategoryId == null || _startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lengkapi semua field terlebih dahulu')));
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tanggal selesai harus setelah tanggal mulai')));
      return;
    }

    setState(() => _loading = true);
    try {
      await supabase.from('leave_requests').insert({
        'employee_id': widget.employeeId,
        'leave_category_id': _selectedCategoryId,
        'start_date': DateFormat('yyyy-MM-dd').format(_startDate!),
        'end_date': DateFormat('yyyy-MM-dd').format(_endDate!),
        'total_days': _totalDays,
        'reason': _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
        'status': 'pending',
      });

      ref.invalidate(_leaveRequestsProvider(widget.employeeId));
      ref.invalidate(_leaveBalancesProvider(widget.employeeId));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pengajuan cuti berhasil dikirim'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengajukan cuti: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(_leaveCategoriesProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: categoriesAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) =>
              Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.danger))),
          data: (categories) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text('Ajukan Cuti',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface)),
              const SizedBox(height: 20),

              // Category
              const Text('Jenis Cuti',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.textMuted.withValues(alpha: 0.2)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategoryId,
                    hint: const Text('Pilih jenis cuti',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 13)),
                    isExpanded: true,
                    items: categories
                        .map((c) => DropdownMenuItem<String>(
                              value: c['id'] as String,
                              child: Text(c['leave_name'] as String,
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedCategoryId = v),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Date range
              const Text('Tanggal',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _DateButton(
                      label: 'Mulai',
                      date: _startDate,
                      onTap: () => _pickDate(true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateButton(
                      label: 'Selesai',
                      date: _endDate,
                      onTap: () => _pickDate(false),
                    ),
                  ),
                ],
              ),
              if (_totalDays > 0) ...[
                const SizedBox(height: 6),
                Text('Total: $_totalDays hari',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500)),
              ],
              const SizedBox(height: 14),

              // Reason
              const Text('Alasan (opsional)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Tulis alasan cuti...',
                  hintStyle: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: AppColors.textMuted.withValues(alpha: 0.2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: AppColors.textMuted.withValues(alpha: 0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primary),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 20),

              // Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _loading ? null : () => _submit(categories),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Kirim Pengajuan',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper Widgets ────────────────────────────────────────────────────────────

class _DateButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  const _DateButton(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.textMuted.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMuted)),
                Text(
                  date != null
                      ? DateFormat('d MMM yyyy', 'id_ID').format(date!)
                      : 'Pilih tanggal',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: date != null
                          ? AppColors.onSurface
                          : AppColors.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppColors.onSurface));
  }
}

class _Shimmer extends StatelessWidget {
  final double height;
  const _Shimmer({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
