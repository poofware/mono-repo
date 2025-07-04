import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/core/app_state/app_state_notifier.dart';
import 'package:poof_admin/features/account/data/models/property_admin.dart';
import 'package:poof_admin/features/account/data/models/property_manager_admin.dart';
import 'package:poof_admin/features/account/presentation/pages/dashboard_page.dart';
import 'package:poof_admin/features/account/presentation/pages/pm_dashboard_page.dart';
import 'package:poof_admin/features/account/presentation/pages/pm_detail_page.dart';
import 'package:poof_admin/features/account/presentation/pages/pm_form_page.dart';
import 'package:poof_admin/features/account/presentation/pages/property_form_page.dart';
import 'package:poof_admin/features/auth/presentation/pages/login_page.dart';
import 'package:poof_admin/features/auth/presentation/pages/session_expired_page.dart';
import 'package:poof_admin/features/auth/presentation/pages/signing_out_page.dart';
import 'package:poof_admin/features/auth/presentation/pages/totp_verify_page.dart';

enum RouteAccess { public, protected, unrestricted }

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

final List<RouteBase> _adminAppRoutes = [
  // --- Public Routes ---
  AppRoute(
    access: RouteAccess.public,
    path: '/',
    name: 'LoginPage',
    builder: (_, __) => const LoginPage(),
  ),
  AppRoute(
    access: RouteAccess.public,
    path: '/verify-totp',
    name: 'TotpVerifyPage',
    builder: (_, __) => const TotpVerifyPage(),
  ),
  // --- Protected Routes ---
  ShellRoute(
    builder: (context, state, child) {
      return DashboardPage(child: child, state: state);
    },
    routes: [
      GoRoute(path: '/dashboard', redirect: (_, __) => '/dashboard/home'),
      GoRoute(
        path: '/dashboard/home',
        name: 'DashboardHomePage',
        builder: (_, __) => const Center(child: Text('Admin Dashboard Home')),
      ),
      // NEW: Property Manager Routes
      GoRoute(
        path: '/dashboard/pms',
        name: 'PmsDashboardPage',
        builder: (_, __) => const PmsDashboardPage(),
        routes: [
          // Create new PM form
          GoRoute(
            path: 'new',
            name: 'PmFormPageNew',
            builder: (context, state) => const PmFormPage(),
          ),
          // Detail page for a specific PM
          GoRoute(
            path: ':pmId',
            name: 'PmsDetailPage',
            builder: (context, state) {
              final pmId = state.pathParameters['pmId']!;
              return PmsDetailPage(pmId: pmId);
            },
            routes: [
              // Edit existing PM form
              GoRoute(
                path: 'edit',
                name: 'PmFormPageEdit',
                builder: (context, state) {
                  final pm = state.extra as PropertyManagerAdmin?;
                  return PmFormPage(pm: pm);
                },
              ),
              // Create new Property for this PM
              GoRoute(
                  path: 'properties/new',
                  name: 'PropertyFormPageNew',
                  builder: (context, state) {
                    final pmId = state.pathParameters['pmId']!;
                    return PropertyFormPage(pmId: pmId);
                  }),
              // Edit existing Property for this PM
              GoRoute(
                  path: 'properties/:propertyId/edit',
                  name: 'PropertyFormPageEdit',
                  builder: (context, state) {
                    final pmId = state.pathParameters['pmId']!;
                    final property = state.extra as PropertyAdmin?;
                    return PropertyFormPage(pmId: pmId, property: property);
                  }),
            ],
          ),
        ],
      ),
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

final Map<String, RouteAccess> _accessByPath = {
  for (final r in _adminAppRoutes.whereType<AppRoute>()) r.path: r.access,
};
final Map<String, RouteAccess> _accessByName = {
  for (final r in _adminAppRoutes.whereType<AppRoute>())
    if (r.name != null) r.name!: r.access,
};

GoRouter createAdminRouter(AppStateNotifier appStateNotifier) {
  return GoRouter(
    debugLogDiagnostics: true,
    refreshListenable: GoRouterRefreshStream(appStateNotifier.stream),
    routes: _adminAppRoutes,
    redirect: (context, state) {
      final loggedIn = appStateNotifier.isLoggedIn;
      final routePath = state.uri.path;
      final routeName = state.name;

      if (routePath.startsWith('/dashboard')) {
        if (!loggedIn) return '/session_expired';
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
        return '/dashboard';
      }

      return null;
    },
  );
}