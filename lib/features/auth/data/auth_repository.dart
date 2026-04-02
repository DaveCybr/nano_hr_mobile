import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_client.dart';

class AuthRepository {
  // Login dengan email + password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  // Logout
  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  // Reset password via email
  Future<void> resetPassword(String email) async {
    await supabase.auth.resetPasswordForEmail(email.trim());
  }

  // Cek apakah employee sudah enroll wajah
  Future<bool> hasFaceToken() async {
    final session = supabase.auth.currentSession;
    if (session == null) return false;

    final data = await supabase
        .from('employees')
        .select('face_token')
        .eq('auth_user_id', session.user.id)
        .maybeSingle();

    return data != null && data['face_token'] != null;
  }

  // Simpan face_token ke tabel employees
  Future<void> saveFaceToken({
    required String faceToken,
    required String facePhotoUrl,
  }) async {
    final session = supabase.auth.currentSession;
    if (session == null) throw Exception('Sesi tidak ditemukan, silakan login ulang.');

    final res = await supabase
        .from('employees')
        .update({
          'face_token': faceToken,
          'face_photo_url': facePhotoUrl,
        })
        .eq('auth_user_id', session.user.id)
        .select('id')
        .maybeSingle();

    if (res == null) {
      throw Exception('Data karyawan tidak ditemukan. Hubungi administrator.');
    }
  }
}
