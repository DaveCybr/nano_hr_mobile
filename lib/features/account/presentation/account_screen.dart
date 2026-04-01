import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/supabase/supabase_client.dart';
import '../../auth/providers/auth_provider.dart' show authRepositoryProvider;
import '../../home/providers/home_provider.dart';
import '../../../shared/models/employee_model.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeeAsync = ref.watch(currentEmployeeProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLow,
      body: employeeAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (_, __) => const Center(
            child: Text('Gagal memuat profil',
                style: TextStyle(color: AppColors.textSecondary))),
        data: (employee) => employee == null
            ? const Center(
                child: Text('Data tidak ditemukan',
                    style: TextStyle(color: AppColors.textSecondary)))
            : _Body(employee: employee),
      ),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _Body extends ConsumerStatefulWidget {
  final EmployeeModel employee;
  const _Body({required this.employee});

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _uploadingPhoto = false;

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final session = supabase.auth.currentSession;
      if (session == null) throw Exception('Tidak ada sesi login');

      final fileName = 'profile_${widget.employee.id}.jpg';
      final response = await http.post(
        Uri.parse(
          '${AppConstants.supabaseUrl}/storage/v1/object/profile-photos/$fileName',
        ),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'apikey': AppConstants.supabaseAnonKey,
          'Content-Type': 'image/jpeg',
          'x-upsert': 'true',
        },
        body: bytes,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Upload gagal: ${response.statusCode}');
      }

      final photoUrl =
          '${AppConstants.supabaseUrl}/storage/v1/object/public/profile-photos/$fileName';
      await supabase
          .from('employees')
          .update({'profile_photo_url': photoUrl})
          .eq('id', widget.employee.id);

      ref.invalidate(currentEmployeeProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto profil berhasil diperbarui'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal upload foto: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee     = widget.employee;
    final group        = employee.group;
    final position     = employee.position;
    final groupName    = group?['name']    as String? ?? '-';
    final positionName = position?['name'] as String? ?? '-';
    final roleLabel    = _roleLabel(employee.accessType);

    return CustomScrollView(
      slivers: [
        // ── Hero ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _Hero(
            employee: employee,
            roleLabel: roleLabel,
            onEditPhoto: _pickAndUploadPhoto,
            uploadingPhoto: _uploadingPhoto,
          ),
        ),

        // ── Info ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _Section(
              title: 'Informasi Akun',
              child: _InfoCard(items: [
                _InfoRow(
                  icon: Icons.badge_outlined,
                  label: 'NIP',
                  value: employee.employeeCode,
                ),
                _InfoRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: employee.email,
                ),
                _InfoRow(
                  icon: Icons.work_outline_rounded,
                  label: 'Jabatan',
                  value: positionName,
                ),
                _InfoRow(
                  icon: Icons.groups_outlined,
                  label: 'Departemen',
                  value: groupName,
                ),
                _InfoRow(
                  icon: Icons.verified_user_outlined,
                  label: 'Tipe Akses',
                  value: roleLabel,
                  isLast: true,
                ),
              ]),
            ),
          ),
        ),

        // ── Pengaturan ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _Section(
              title: 'Pengaturan',
              child: _ActionCard(items: [
                _ActionRow(
                  icon: Icons.face_retouching_natural_rounded,
                  iconBg: const Color(0xFFE8F5EE),
                  iconColor: AppColors.primary,
                  label: 'Perbarui Data Wajah',
                  onTap: () => context.push('/enroll-face'),
                ),
                _ActionRow(
                  icon: Icons.lock_reset_rounded,
                  iconBg: const Color(0xFFEFF6FF),
                  iconColor: const Color(0xFF1976D2),
                  label: 'Ubah Password',
                  isLast: true,
                  onTap: () => context.push('/forgot-password'),
                ),
              ]),
            ),
          ),
        ),

        // ── Logout ────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _ActionCard(items: [
              _ActionRow(
                icon: Icons.logout_rounded,
                iconBg: AppColors.errorContainer,
                iconColor: AppColors.danger,
                label: 'Keluar dari Akun',
                textColor: AppColors.danger,
                isLast: true,
                showChevron: false,
                onTap: () => _showLogoutDialog(context),
              ),
            ]),
          ),
        ),

        // ── Footer ────────────────────────────────────────────────────
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Column(children: [
              Text(
                AppConstants.appName,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    ),
              ),
              SizedBox(height: 2),
              Text(
                'Versi 1.0.0',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  String _roleLabel(String t) {
    switch (t) {
      case 'admin':   return 'Admin';
      case 'manager': return 'Manajer';
      default:        return 'Pegawai';
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56, height: 56,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.errorContainer),
                child: const Icon(Icons.logout_rounded,
                    color: AppColors.danger, size: 28),
              ),
              const SizedBox(height: 16),
              const Text('Keluar dari Akun?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.onSurface,
                      )),
              const SizedBox(height: 6),
              const Text('Anda akan keluar dari sesi ini.',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      ),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.onSurface,
                      side: const BorderSide(
                          color: AppColors.surfaceContainerHigh),
                      shape: const StadiumBorder(),
                      padding:
                          const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Batal',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            )),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ref
                          .read(authRepositoryProvider)
                          .signOut();
                      if (context.mounted) context.go('/login');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: const StadiumBorder(),
                      padding:
                          const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Keluar',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            )),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  final EmployeeModel employee;
  final String roleLabel;
  final VoidCallback onEditPhoto;
  final bool uploadingPhoto;
  const _Hero({
    required this.employee,
    required this.roleLabel,
    required this.onEditPhoto,
    required this.uploadingPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final positionName =
        (employee.position?['name'] as String? ?? '').trim();

    return Container(
      color: AppColors.surfaceContainerLow,
      child: Column(
        children: [
          // ── App bar ──────────────────────────────────────────────
          const SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Profil',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ),

          // ── Profile card ─────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                // Avatar
                GestureDetector(
                  onTap: uploadingPhoto ? null : onEditPhoto,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 88, height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE8F5EE),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              width: 3),
                        ),
                        child: ClipOval(
                          child: uploadingPhoto
                              ? const Center(
                                  child: SizedBox(
                                    width: 28, height: 28,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: AppColors.primary),
                                  ),
                                )
                              : (employee.profilePhotoUrl ?? employee.facePhotoUrl) != null
                                  ? Image.network(
                                      (employee.profilePhotoUrl ?? employee.facePhotoUrl)!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                          Icons.person_rounded,
                                          color: AppColors.primary,
                                          size: 44),
                                    )
                                  : const Icon(Icons.person_rounded,
                                      color: AppColors.primary, size: 44),
                        ),
                      ),
                      Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                          border: Border.all(
                              color: AppColors.surfaceContainerLowest,
                              width: 2),
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 13),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Name
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    employee.fullName,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.onSurface,
                        letterSpacing: -0.3,
                        ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                const SizedBox(height: 10),

                // Badges
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Badge(label: roleLabel),
                    if (positionName.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _Badge(
                          label: positionName,
                          bg: const Color(0xFFE0F2FE),
                          fg: const Color(0xFF0369A1)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Badge({
    required this.label,
    this.bg = const Color(0xFFDCFCE7),
    this.fg = const Color(0xFF166534),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: fg,
              )),
    );
  }
}

// ── Section wrapper ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 0.8,
                ),
          ),
        ),
        child,
      ],
    );
  }
}

// ── Info Card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final List<_InfoRow> items;
  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: items),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: isLast
          ? null
          : const BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: AppColors.surfaceContainerLow, width: 1))),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Color(0xFFE8F5EE)),
            child: Icon(icon, color: AppColors.primary, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        )),
                const SizedBox(height: 1),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface,
                        )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action Card ───────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final List<_ActionRow> items;
  const _ActionCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: items),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final Color textColor;
  final bool isLast;
  final bool showChevron;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    this.textColor = AppColors.onSurface,
    this.isLast = false,
    this.showChevron = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: isLast ? Radius.zero : const Radius.circular(16),
        bottom: isLast ? const Radius.circular(16) : Radius.zero,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: isLast
            ? null
            : const BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: AppColors.surfaceContainerLow, width: 1))),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: iconBg),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                      )),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

