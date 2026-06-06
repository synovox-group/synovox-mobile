import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/calls/calls_screen.dart';
import 'screens/calls/call_detail_screen.dart';
import 'screens/assistants/assistants_screen.dart';
import 'screens/assistants/assistant_detail_screen.dart';
import 'screens/appointments/appointments_screen.dart';
import 'screens/appointments/appointment_detail_screen.dart';
import 'screens/contacts/contacts_screen.dart';
import 'screens/contacts/contact_detail_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/business_hours_screen.dart';
import 'screens/settings/holidays_screen.dart';
import 'screens/settings/forwarding_screen.dart';
import 'screens/settings/phone_numbers_screen.dart';
import 'screens/analytics/analytics_screen.dart';
import 'widgets/main_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Only refresh the router when the token changes (login/logout), not on loading ticks.
  final authNotifier = ValueNotifier<AuthState>(ref.read(authProvider));
  ref.listen<AuthState>(authProvider, (prev, next) {
    if (prev?.token != next.token) authNotifier.value = next;
  });

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final isLoggedIn = authNotifier.value.token != null;

      if (loc.startsWith('/splash')) return null;
      if (!isLoggedIn && !loc.startsWith('/login')) return '/login';
      if (isLoggedIn && loc.startsWith('/login')) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (_, __, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/calls',
            builder: (_, __) => const CallsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => CallDetailScreen(
                  callId: int.parse(state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/contacts',
            builder: (_, __) => const ContactsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => ContactDetailScreen(
                  contactId: int.parse(state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/appointments',
            builder: (_, __) => const AppointmentsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => AppointmentDetailScreen(
                  appointmentId: int.parse(state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/assistants',
            builder: (_, __) => const AssistantsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => AssistantDetailScreen(
                  assistantId: int.parse(state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/analytics',
            builder: (_, __) => const AnalyticsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'business-hours',
                builder: (_, __) => const BusinessHoursScreen(),
              ),
              GoRoute(
                path: 'holidays',
                builder: (_, __) => const HolidaysScreen(),
              ),
              GoRoute(
                path: 'forwarding',
                builder: (_, __) => const ForwardingScreen(),
              ),
              GoRoute(
                path: 'phone-numbers',
                builder: (_, __) => const PhoneNumbersScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    authNotifier.dispose();
  });

  return router;
});
