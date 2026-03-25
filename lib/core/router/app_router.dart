import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/enroll_face_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/home/presentation/ringkasan_screen.dart';
import '../../features/attendance/presentation/checkin_location_screen.dart';
import '../../features/attendance/presentation/checkin_face_screen.dart';
import '../../features/attendance/presentation/checkout_location_screen.dart';
import '../../features/attendance/presentation/attendance_history_screen.dart';
import '../../features/leave/presentation/leave_screen.dart';
import '../../features/overtime/presentation/overtime_screen.dart';
import '../../features/schedule/presentation/schedule_screen.dart';
import '../../features/notification/presentation/notification_screen.dart';
import '../../features/account/presentation/account_screen.dart';
import '../supabase/supabase_client.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) async {
      final session = supabase.auth.currentSession;
      final isLoggedIn = session != null;
      final loc = state.matchedLocation;

      // Belum login → ke login
      if (!isLoggedIn) {
        if (loc == '/login' || loc == '/forgot-password') return null;
        return '/login';
      }

      // Sudah login, cek face_token
      if (loc == '/login') {
        final emp = await supabase
            .from('employees')
            .select('face_token')
            .eq('auth_user_id', session.user.id)
            .maybeSingle();

        final hasFace = emp != null && emp['face_token'] != null;
        return hasFace ? '/home' : '/enroll-face';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login',           builder: (ctx, state) => const LoginScreen()),
      GoRoute(path: '/forgot-password', builder: (ctx, state) => const ForgotPasswordScreen()),
      GoRoute(path: '/enroll-face',     builder: (ctx, state) => const EnrollFaceScreen()),
      GoRoute(path: '/home',            builder: (ctx, state) => const HomeScreen()),
      GoRoute(path: '/ringkasan',       builder: (ctx, state) => const RingkasanScreen()),
      GoRoute(path: '/checkin/location',   builder: (ctx, state) => const CheckinLocationScreen()),
      GoRoute(
        path: '/checkin/face',
        builder: (ctx, state) => CheckinFaceScreen(
          locationData:
              (state.extra as Map<String, dynamic>?) ?? {},
        ),
      ),
      GoRoute(path: '/checkout/location',  builder: (ctx, state) => const CheckoutLocationScreen()),
      GoRoute(path: '/attendance/history', builder: (ctx, state) => const AttendanceHistoryScreen()),
      GoRoute(path: '/leave',          builder: (ctx, state) => const LeaveScreen()),
      GoRoute(path: '/overtime',       builder: (ctx, state) => const OvertimeScreen()),
      GoRoute(path: '/schedule',       builder: (ctx, state) => const ScheduleScreen()),
      GoRoute(path: '/notifications',  builder: (ctx, state) => const NotificationScreen()),
      GoRoute(path: '/account',        builder: (ctx, state) => const AccountScreen()),
    ],
  );
});
