import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:poof_pm/core/app_state/app_state_notifier.dart';
import 'package:poof_pm/features/auth/presentation/pages/welcome_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/login_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/create_account_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/company_address_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/email_verification_info_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/verify_email_code_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/totp_setup_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/signing_out_page.dart';
import 'package:poof_pm/features/auth/presentation/pages/session_expired_page.dart';

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

/// The list of routes for the PM app. We mark each route as
/// public, protected, or unrestricted, then define
/// path, name, and builder.
final List<AppRoute> _pmAppRoutes = [
  // 1) A public route for the welcome / landing page
  AppRoute(
    access: RouteAccess.public,
    path: '/',
    name: 'WelcomePage',
    builder: (_, __) => const WelcomePage(),
  ),

  // 2) Public route: Login
  AppRoute(
    access: RouteAccess.public,
    path: '/login',
    name: 'LoginPage',
    builder: (_, __) => const LoginPage(),
  ),

  // 3) Public route: Create Account
  AppRoute(
    access: RouteAccess.public,
    path: '/create_account',
    name: 'CreateAccountPage',
    builder: (_, __) => const CreateAccountPage(),
  ),

  // 4) Public route: Company Address
  AppRoute(
    access: RouteAccess.public,
    path: '/company_address',
    name: 'CompanyAddressPage',
    builder: (_, __) => const CompanyAddressPage(),
  ),

  // 5) Public route: Email Verification Info
  AppRoute(
    access: RouteAccess.public,
    path: '/email_verification_info',
    name: 'EmailVerificationInfoPage',
    builder: (_, __) => const EmailVerificationInfoPage(),
  ),

  // 6) Public route: Verify Email Code
  AppRoute(
    access: RouteAccess.public,
    path: '/verify_email_code',
    name: 'VerifyEmailCodePage',
    builder: (_, __) => const VerifyEmailCodePage(),
  ),

  // 7) Public route: TOTP Setup
  AppRoute(
    access: RouteAccess.public,
    path: '/totp_setup',
    name: 'TotpSetupPage',
    builder: (_, __) => const TotpSetupPage(),
  ),

  // 8) Protected route: The main PM app screen, e.g. /main
  //    (requires a logged-in user)
  AppRoute(
    access: RouteAccess.protected,
    path: '/main',
    name: 'MainPage',
    builder: (_, __) {
      // You might have a PM main home or tabs here
      return const Scaffold(
        body: Center(child: Text('Main PM screen (protected)')),
      );
    },
  ),

  // 9) Unrestricted route: Signing Out
  AppRoute(
    access: RouteAccess.unrestricted,
    path: '/signing_out',
    name: 'SigningOutPage',
    builder: (_, __) => const SigningOutPage(),
  ),

  // 10) Unrestricted route: Session Expired
  AppRoute(
    access: RouteAccess.unrestricted,
    path: '/session_expired',
    name: 'SessionExpiredPage',
    builder: (_, __) => const SessionExpiredPage(),
  ),
];

/// For easy lookups by name or path
final Map<String, RouteAccess> _accessByPath = {
  for (final r in _pmAppRoutes) r.path: r.access,
};
final Map<String, RouteAccess> _accessByName = {
  for (final r in _pmAppRoutes) r.name!: r.access,
};

/// Creates the router, wiring up the [redirect] logic 
/// and hooking into the [appStateNotifier] to refresh
/// whenever login state changes.
GoRouter createPmRouter(AppStateNotifier appStateNotifier) {
  return GoRouter(
    debugLogDiagnostics: true,
    // watch changes from the appState notifier so we can re-check redirect
    refreshListenable: GoRouterRefreshStream(appStateNotifier.stream),
    routes: _pmAppRoutes,
    redirect: (context, state) {
      final loggedIn = appStateNotifier.isLoggedIn;
      final routeName = state.name;
      final routePath = state.uri.path;

      // Check route access from either path or name.
      // If not found, default to protected or some fallback.
      final access = _accessByPath[routePath] ??
          _accessByName[routeName ?? ''] ??
          RouteAccess.protected;

      // Decide on a redirect:
      if (access == RouteAccess.unrestricted) {
        // Always allowed
        return null;
      }
      if (!loggedIn && access == RouteAccess.protected) {
        // Must redirect to session expired or welcome
        return '/session_expired';
      }
      if (loggedIn && access == RouteAccess.public) {
        // Already logged in, skip public route
        return '/main';
      }
      // Otherwise, no change
      return null;
    },
  );
}

