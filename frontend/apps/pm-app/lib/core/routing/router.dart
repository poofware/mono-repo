// lib/core/routing/router.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:poof_pm/core/app_state/app_state_notifier.dart';
import 'package:poof_pm/features/auth/presentation/pages/welcome_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/create_account_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/company_address_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/email_verification_info_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/verify_email_code_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/totp_setup_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/signing_out_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/session_expired_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/qr_info_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/login_verify_code_page.dart';
 
// Import the pages for the dashboard shell
import 'package:poof_pm/features/jobs/presentation/pages/main_dashboard_page.dart';
import 'package:poof_pm/features/jobs/presentation/pages/job_history_page.dart';


/// A small enum describing who can access a route:
/// - public: requires logged-out
/// - protected: requires logged-in
/// - unrestricted: open to all
enum RouteAccess { public, protected, unrestricted }

/// A custom GoRoute that stores `access` so we can do
/// a global redirect check based on login state.
class AppRoute extends GoRoute {
  final RouteAccess access;

  AppRoute({
    required this.access,
    required super.path,
    required super.name,
    required super.builder,
    super.routes,
  });
}

/// A helper that listens to changes from our [AppStateNotifier]
/// and calls `notifyListeners()` so GoRouter knows to re-check
/// its `redirect` logic.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// MODIFICATION: Change list type to RouteBase to allow ShellRoute.
final List<RouteBase> _pmAppRoutes = [
  // --- Public Routes ---
  AppRoute(
    access: RouteAccess.public,
    path: '/',
    name: 'WelcomePage',
    builder: (_, __) => const WelcomePage(),
  ),
  AppRoute(
    access: RouteAccess.public,
    path: '/login-verify-code',
    name: 'LoginVerifyCodePage',
    builder: (_, state) {
      // This route requires an email to be passed as an extra parameter.
      final email = state.extra as String;
      return LoginVerifyCodePage(email: email);
    },
   ),
  AppRoute(
    access: RouteAccess.public,
    path: '/create_account',
    name: 'CreateAccountPage',
    builder: (_, __) => const CreateAccountPage(),
  ),
  AppRoute(
    access: RouteAccess.public,
    path: '/company_address',
    name: 'CompanyAddressPage',
    builder: (_, __) => const CompanyAddressPage(),
  ),
  AppRoute(
    access: RouteAccess.public,
    path: '/email_verification_info',
    name: 'EmailVerificationInfoPage',
    builder: (_, __) => const EmailVerificationInfoPage(),
  ),
  AppRoute(
    access: RouteAccess.public,
    path: '/verify_email_code',
    name: 'VerifyEmailCodePage',
    builder: (_, __) => const VerifyEmailCodePage(),
  ),
  AppRoute(
    access: RouteAccess.public,
    path: '/totp_setup',
    name: 'TotpSetupPage',
    builder: (_, __) => const TotpSetupPage(),
  ),
  AppRoute(
    access: RouteAccess.public,
    path: '/qr_info',
    name: 'QrInfoPage',
    builder: (_, __) => const QrInfoPage(),
  ),

  // --- Protected Routes (wrapped in a ShellRoute) ---
  ShellRoute(
    builder: (context, state, child) {
      return MainDashboardPage(child: child, state: state);
    },
    routes: <RouteBase>[
      // Redirect '/main' to the new jobs page by default.
      GoRoute(
        path: '/main',
        redirect: (_, __) => '/main/jobs',
      ),
      GoRoute(
        path: '/main/jobs',
        name: 'JobHistoryPage',
        builder: (BuildContext context, GoRouterState state) {
          return const JobHistoryPage();
        },
      ),
      // REMOVED: The settings page is now a dialog, so the route is no longer needed.
    ],
  ),
  
  // --- Unrestricted Routes ---
  AppRoute(
    access: RouteAccess.unrestricted,
    path: '/signing_out',
    name: 'SigningOutPage',
    builder: (_, __) => const SigningOutPage(),
  ),
  AppRoute(
    access: RouteAccess.unrestricted,
    path: '/session_expired',
    name: 'SessionExpiredPage',
    builder: (_, __) => const SessionExpiredPage(),
  ),
];

// MODIFICATION: Filter for AppRoute type since the list now contains ShellRoute.
final Map<String, RouteAccess> _accessByPath = {
  for (final r in _pmAppRoutes.whereType<AppRoute>()) r.path: r.access,
};
final Map<String, RouteAccess> _accessByName = {
  for (final r in _pmAppRoutes.whereType<AppRoute>()) if (r.name != null) r.name!: r.access,
};

/// Creates the router, wiring up the [redirect] logic.
GoRouter createPmRouter(AppStateNotifier appStateNotifier) {
  return GoRouter(
    debugLogDiagnostics: true,
    refreshListenable: GoRouterRefreshStream(appStateNotifier.stream),
    routes: _pmAppRoutes,
    redirect: (context, state) {
      final loggedIn = appStateNotifier.isLoggedIn;
      final routePath = state.uri.path;
      final routeName = state.name;
       // Guard against direct navigation to the login verification page
      // without providing an email.
      if (routePath == '/login-verify-code' && state.extra is! String) {
        return '/';
      }

      if (routePath.startsWith('/main')) {
        if (!loggedIn) {
          return '/session_expired'; 
        }
        return null; 
      }

      final access = _accessByPath[routePath] ??
          _accessByName[routeName ?? ''] ??
          RouteAccess.protected;

      if (access == RouteAccess.unrestricted) {
        return null;
      }
      if (!loggedIn && access == RouteAccess.protected) {
        return '/session_expired';
      }
      if (loggedIn && access == RouteAccess.public) {
        return '/main';
      }

      return null;
    },
  );
}