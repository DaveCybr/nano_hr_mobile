import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../home/providers/home_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _overtimeCategoriesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase.from('overtime_categories').select().order('name_id');
  return (data as List).cast<Map<String, dynamic>>();
});

final _overtimeRequestsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, employeeId) async {
  final data = await supabase
      .from('overtime_requests')
      .select('*, overtime_category:overtime_categories(name_id, code), admin_notes')
      .eq('employee_id', employeeId)
      .order('overtime_date', ascending: false);
  return (data as List).cast<Map<String, dynamic>>();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class OvertimeScreen extends ConsumerWidget {
  const OvertimeScreen({super.key});

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
        title: const Text('Lembur'),
      ),
      floatingActionButton: employeeAsync.valueOrNull == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => OvertimeSubmitSheet(
                    employeeId: employeeAsync.value!.id),
              ),
              backgroundColor: const Color(0xFFF97316),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajukan Lembur',
                  style: TextStyle(fontWeight: FontWeight.w600)),
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
              return const Center(child: Text('Data karyawan tidak ditemukan'));
            }
            return _OvertimeBody(employeeId: employee.id);
          },
        ),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _OvertimeBody extends ConsumerWidget {
  final String employeeId;
  const _OvertimeBody({required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(_overtimeRequestsProvider(employeeId));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(_overtimeRequestsProvider(employeeId));
      },
      child: requestsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
            child: Text('Gagal memuat: $e',
                style: const TextStyle(color: AppColors.danger))),
        data: (requests) => requests.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Column(
                    children: [
                      Icon(Icons.hourglass_empty_rounded,
                          color: AppColors.textMuted, size: 52),
                      SizedBox(height: 12),
                      Text('Belum ada pengajuan lembur',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: requests.length,
                itemBuilder: (_, i) =>
                    _OvertimeCard(request: requests[i]),
              ),
      ),
    );
  }
}

// ── Request Card ──────────────────────────────────────────────────────────────

class _OvertimeCard extends StatelessWidget {
  final Map<String, dynamic> request;
  const _OvertimeCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final category = request['overtime_category'] as Map<String, dynamic>?;
    final name = category?['name_id'] ?? '-';
    final status = request['status'] as String? ?? 'pending';
    final date = DateTime.tryParse(request['overtime_date'] ?? '');
    final startTime = request['start_time'] as String?;
    final endTime = request['end_time'] as String?;
    final totalMin = request['total_minutes'] as int? ?? 0;
    final reason = request['reason'] as String?;
    final adminNotes = request['admin_notes'] as String?;
    final createdAt = DateTime.tryParse(request['created_at'] ?? '');

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

    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    final durationStr = totalMin > 0
        ? (h > 0 ? '${h}j ${m}m' : '${m}m')
        : '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: statusColor, width: 3)),
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
              Text(
                date != null
                    ? DateFormat('EEEE, d MMM yyyy', 'id_ID').format(date)
                    : '-',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 13, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                startTime != null && endTime != null
                    ? '${_trimTime(startTime)} – ${_trimTime(endTime)}'
                    : '-',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(durationStr,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF97316))),
              ),
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
          if (status == 'rejected' && adminNotes != null && adminNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 13, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      adminNotes,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (createdAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Diajukan ${DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(createdAt.toLocal())}',
              style:
                  const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  String _trimTime(String t) => t.length >= 5 ? t.substring(0, 5) : t;
}

// ── Submit Sheet ──────────────────────────────────────────────────────────────

class OvertimeSubmitSheet extends ConsumerStatefulWidget {
  final String employeeId;
  const OvertimeSubmitSheet({required this.employeeId, super.key});

  @override
  ConsumerState<OvertimeSubmitSheet> createState() =>
      _OvertimeSubmitSheetState();
}

class _OvertimeSubmitSheetState extends ConsumerState<OvertimeSubmitSheet> {
  String? _selectedCategoryId;
  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final _reasonCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  int get _totalMinutes {
    if (_startTime == null || _endTime == null) return 0;
    final start = _startTime!.hour * 60 + _startTime!.minute;
    final end = _endTime!.hour * 60 + _endTime!.minute;
    return end > start ? end - start : 0;
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('id', 'ID'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (_startTime ?? const TimeOfDay(hour: 17, minute: 0))
          : (_endTime ?? const TimeOfDay(hour: 19, minute: 0)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_selectedCategoryId == null ||
        _date == null ||
        _startTime == null ||
        _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Lengkapi semua field terlebih dahulu')));
      return;
    }
    if (_totalMinutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Waktu selesai harus setelah waktu mulai')));
      return;
    }

    setState(() => _loading = true);
    try {
      await supabase.from('overtime_requests').insert({
        'employee_id': widget.employeeId,
        'overtime_category_id': _selectedCategoryId,
        'overtime_date': DateFormat('yyyy-MM-dd').format(_date!),
        'start_time': '${_fmtTime(_startTime!)}:00',
        'end_time': '${_fmtTime(_endTime!)}:00',
        'total_minutes': _totalMinutes,
        'reason': _reasonCtrl.text.trim().isEmpty
            ? null
            : _reasonCtrl.text.trim(),
        'status': 'pending',
      });

      ref.invalidate(_overtimeRequestsProvider(widget.employeeId));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pengajuan lembur berhasil dikirim'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengajukan lembur: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(_overtimeCategoriesProvider);
    final totalMin = _totalMinutes;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    final durationStr =
        totalMin > 0 ? (h > 0 ? '$h jam $m menit' : '$m menit') : null;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: categoriesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
          ),
          error: (e, _) => Center(
              child: Text('Error: $e',
                  style: const TextStyle(color: AppColors.danger))),
          data: (categories) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const Text('Ajukan Lembur',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface)),
              const SizedBox(height: 20),

              // Category
              _FieldLabel('Kategori Lembur'),
              const SizedBox(height: 6),
              _Dropdown(
                value: _selectedCategoryId,
                hint: 'Pilih kategori',
                items: categories
                    .map((c) => DropdownMenuItem<String>(
                          value: c['id'] as String,
                          child: Text(c['name_id'] as String,
                              style: const TextStyle(fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedCategoryId = v),
              ),
              const SizedBox(height: 14),

              // Date
              _FieldLabel('Tanggal Lembur'),
              const SizedBox(height: 6),
              _TapField(
                icon: Icons.calendar_today_rounded,
                text: _date != null
                    ? DateFormat('EEEE, d MMM yyyy', 'id_ID').format(_date!)
                    : 'Pilih tanggal',
                hasValue: _date != null,
                onTap: _pickDate,
              ),
              const SizedBox(height: 14),

              // Time range
              _FieldLabel('Waktu'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _TapField(
                      icon: Icons.schedule_rounded,
                      text: _startTime != null
                          ? _fmtTime(_startTime!)
                          : 'Mulai',
                      hasValue: _startTime != null,
                      onTap: () => _pickTime(true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TapField(
                      icon: Icons.schedule_rounded,
                      text:
                          _endTime != null ? _fmtTime(_endTime!) : 'Selesai',
                      hasValue: _endTime != null,
                      onTap: () => _pickTime(false),
                    ),
                  ),
                ],
              ),
              if (durationStr != null) ...[
                const SizedBox(height: 6),
                Text('Total: $durationStr',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFF97316),
                        fontWeight: FontWeight.w500)),
              ],
              const SizedBox(height: 14),

              // Reason
              _FieldLabel('Alasan (opsional)'),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Tulis alasan lembur...',
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
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
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

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary));
  }
}

class _Dropdown extends StatelessWidget {
  final String? value;
  final String hint;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _Dropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textMuted.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint,
              style:
                  const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TapField extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool hasValue;
  final VoidCallback onTap;

  const _TapField({
    required this.icon,
    required this.text,
    required this.hasValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.textMuted.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(text,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        hasValue ? FontWeight.w600 : FontWeight.normal,
                    color: hasValue
                        ? AppColors.onSurface
                        : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}
