import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../home/providers/home_provider.dart';

// ── Providers ──────────────────────────────────────────────────────────────────

final _newsFeedsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await supabase
      .from('news_feeds')
      .select()
      .eq('is_published', true)
      .order('published_at', ascending: false);
  return (data as List).cast<Map<String, dynamic>>();
});

final _approvalUpdatesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, employeeId) async {
  final leaves = await supabase
      .from('leave_requests')
      .select('id, status, created_at, updated_at, leave_category:leave_categories!left(leave_name)')
      .eq('employee_id', employeeId)
      .inFilter('status', ['approved', 'rejected'])
      .isFilter('deleted_at', null)
      .order('updated_at', ascending: false)
      .limit(20);

  final overtimes = await supabase
      .from('overtime_requests')
      .select('id, status, created_at, updated_at, overtime_category:overtime_categories!left(name_id)')
      .eq('employee_id', employeeId)
      .inFilter('status', ['approved', 'rejected'])
      .order('updated_at', ascending: false)
      .limit(20);

  final result = <Map<String, dynamic>>[];

  for (final r in leaves as List) {
    final cat = r['leave_category'] as Map<String, dynamic>?;
    result.add({
      'type': 'leave',
      'status': r['status'],
      'title': cat?['leave_name'] ?? 'Cuti',
      'updated_at': r['updated_at'] ?? r['created_at'],
    });
  }
  for (final r in overtimes as List) {
    final cat = r['overtime_category'] as Map<String, dynamic>?;
    result.add({
      'type': 'overtime',
      'status': r['status'],
      'title': cat?['name_id'] ?? 'Lembur',
      'updated_at': r['updated_at'] ?? r['created_at'],
    });
  }

  result.sort((a, b) =>
      (b['updated_at'] as String).compareTo(a['updated_at'] as String));
  return result;
});

// ── Screen ─────────────────────────────────────────────────────────────────────

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeeAsync = ref.watch(currentEmployeeProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Text(
                'Notifikasi',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            Expanded(
              child: employeeAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: AppColors.primary)),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (employee) {
                  if (employee == null) return const SizedBox();
                  return _NotifBody(employeeId: employee.id);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotifBody extends ConsumerWidget {
  final String employeeId;
  const _NotifBody({required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedsAsync = ref.watch(_newsFeedsProvider);
    final approvalsAsync = ref.watch(_approvalUpdatesProvider(employeeId));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(_newsFeedsProvider);
        ref.invalidate(_approvalUpdatesProvider(employeeId));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        children: [
          // ── Approval Updates ──────────────────────────────────────────
          approvalsAsync.when(
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
            data: (approvals) {
              if (approvals.isEmpty) return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Status Pengajuan'),
                  ...approvals.map((a) => _ApprovalCard(item: a)),
                  const SizedBox(height: 8),
                ],
              );
            },
          ),

          // ── News Feeds ────────────────────────────────────────────────
          feedsAsync.when(
            loading: () => const Center(
                child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppColors.primary),
            )),
            error: (_, __) => const SizedBox(),
            data: (feeds) {
              if (feeds.isEmpty) {
                return approvalsAsync.maybeWhen(
                  data: (a) => a.isEmpty ? _emptyState() : const SizedBox(),
                  orElse: () => _emptyState(),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Pengumuman'),
                  ...feeds.map((f) => _FeedCard(feed: f)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 56, color: AppColors.textMuted),
            SizedBox(height: 12),
            Text('Belum ada notifikasi',
                style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
          ],
        ),
      );
}

// ── Widgets ────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
      );
}

class _ApprovalCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ApprovalCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isApproved = item['status'] == 'approved';
    final isLeave = item['type'] == 'leave';
    final color = isApproved ? AppColors.success : AppColors.danger;
    final statusLabel = isApproved ? 'Disetujui' : 'Ditolak';
    final typeLabel = isLeave ? 'Pengajuan Cuti' : 'Pengajuan Lembur';
    final title = item['title'] as String;
    final updatedAt = _fmtDate(item['updated_at'] as String?);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isApproved ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(typeLabel,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 2),
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color)),
              ),
              const SizedBox(height: 4),
              Text(updatedAt,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('d MMM, HH:mm', 'id_ID').format(dt);
    } catch (_) {
      return '';
    }
  }
}

class _FeedCard extends StatelessWidget {
  final Map<String, dynamic> feed;
  const _FeedCard({required this.feed});

  @override
  Widget build(BuildContext context) {
    final title = feed['title'] as String;
    final content = feed['content'] as String?;
    final imageUrl = feed['image_url'] as String?;
    final publishedAt = _fmtDate(
        (feed['published_at'] ?? feed['created_at']) as String?);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl != null)
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.network(
                imageUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.campaign_rounded,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    const Text('Pengumuman',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.primary)),
                    const Spacer(),
                    Text(publishedAt,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface)),
                if (content != null && content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('d MMM yyyy', 'id_ID').format(dt);
    } catch (_) {
      return '';
    }
  }
}
