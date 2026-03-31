import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/enroll_face_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/ringkasan/presentation/ringkasan_screen.dart';
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
import '../shell/main_shell.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) async {
      final session = supabase.auth.currentSession;
      final isLoggedIn = session != null;
      final loc = state.matchedLocation;

      if (loc == '/splash') return null;

      if (!isLoggedIn) {
        if (loc == '/login' || loc == '/forgot-password') return null;
        return '/login';
      }

      if (loc == '/enroll-face') return null;

      if (loc == '/login' || loc == '/home') {
        final emp = await supabase
            .from('employees')
            .select('face_token')
            .eq('auth_user_id', session.user.id)
            .maybeSingle();
        final hasFace = emp != null && emp['face_token'] != null;
        if (!hasFace) return '/enroll-face';
        if (loc == '/login') return '/home';
      }

      return null;
    },
    routes: [
      // ── Splash ──────────────────────────────────────────────────────
      GoRoute(path: '/splash', builder: (ctx, s) => const SplashScreen()),

      // ── Auth (no shell) ─────────────────────────────────────────────
      GoRoute(path: '/login',           builder: (ctx, s) => const LoginScreen()),
      GoRoute(path: '/forgot-password', builder: (ctx, s) => const ForgotPasswordScreen()),
      GoRoute(path: '/enroll-face',     builder: (ctx, s) => const EnrollFaceScreen()),

      // ── Flow routes (no shell) ──────────────────────────────────────
      GoRoute(path: '/ringkasan',        builder: (ctx, s) => const RingkasanScreen()),
      GoRoute(path: '/checkin/location', builder: (ctx, s) => const CheckinLocationScreen()),
      GoRoute(
        path: '/checkin/face',
        builder: (ctx, s) => CheckinFaceScreen(
          locationData: (s.extra as Map<String, dynamic>?) ?? {},
        ),
      ),
      GoRoute(path: '/checkout/location',  builder: (ctx, s) => const CheckoutLocationScreen()),
      GoRoute(path: '/attendance/history', builder: (ctx, s) => const AttendanceHistoryScreen()),
      GoRoute(path: '/leave',    builder: (ctx, s) => const LeaveScreen()),
      GoRoute(path: '/overtime', builder: (ctx, s) => const OvertimeScreen()),

      // ── Main tabs (persistent shell) ────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (ctx, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (ctx, s) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/notifications', builder: (ctx, s) => const NotificationScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/schedule', builder: (ctx, s) => const ScheduleScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/account', builder: (ctx, s) => const AccountScreen()),
          ]),
        ],
      ),
    ],
  );
});
