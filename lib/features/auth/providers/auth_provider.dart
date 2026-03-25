import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/supabase/supabase_client.dart';
import '../data/auth_repository.dart';

// Current Supabase session
final sessionProvider = StreamProvider<Session?>((ref) {
  return supabase.auth.onAuthStateChange.map((event) => event.session);
});

// Current employee data (fetched after login)
final currentEmployeeProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final session = supabase.auth.currentSession;
  if (session == null) return null;

  final data = await supabase
      .from('employees')
      .select('*, group:groups(name), position:positions(name)')
      .eq('auth_user_id', session.user.id)
      .eq('is_active', true)
      .maybeSingle();

  return data;
});

// Auth repository provider
final authRepositoryProvider = Provider((ref) => AuthRepository());
