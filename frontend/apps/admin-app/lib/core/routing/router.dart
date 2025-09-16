import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/core/app_state/app_state_notifier.dart';
import 'package:poof_admin/features/account/data/models/pm_models.dart';
import 'package:poof_admin/features/account/presentation/pages/building_form_page.dart';
import 'package:poof_admin/features/account/presentation/pages/dashboard_page.dart';
import 'package:poof_admin/features/account/presentation/pages/dumpster_form_page.dart';
import 'package:poof_admin/features/jobs/presentation/pages/job_definition_form_page.dart';
import 'package:poof_admin/features/account/presentation/pages/pm_dashboard_page.dart';
import 'package:poof_admin/features/account/presentation/pages/pm_detail_page.dart';
import 'package:poof_admin/features/account/presentation/pages/pm_form_page.dart';
import 'package:poof_admin/features/account/presentation/pages/property_form_page.dart';
import 'package:poof_admin/features/account/presentation/pages/unit_form_page.dart';
import 'package:poof_admin/features/account/presentation/pages/agent_form_page.dart';
import 'package:poof_admin/features/account/presentation/pages/agents_dashboard_page.dart';
import 'package:poof_admin/features/account/data/models/agent_admin.dart';
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
      // NEW: Agents Routes
      GoRoute(
        path: '/dashboard/agents',
        name: 'AgentsDashboardPage',
        builder: (_, __) => const AgentsDashboardPage(),
        routes: [
          GoRoute(
            path: 'new',
            name: 'AgentFormPageNewRoot',
            builder: (context, state) => const AgentFormPage(),
          ),
          GoRoute(
            path: 'edit',
            name: 'AgentFormPageEditRoot',
            builder: (context, state) {
              final agent = state.extra as AgentAdmin?;
              return AgentFormPage(agent: agent);
            },
          ),
        ],
      ),
      // NEW: Property Manager Routes
      GoRoute(
        path: '/dashboard/pms',
        name: 'PmsDashboardPage',
        builder: (_, __) => const PmsDashboardPage(),
        routes: [
          // Agents
          GoRoute(
            path: 'agents/new',
            name: 'AgentFormPageNew',
            builder: (context, state) => const AgentFormPage(),
          ),
          GoRoute(
            path: 'agents/edit',
            name: 'AgentFormPageEdit',
            builder: (context, state) {
              final agent = state.extra as AgentAdmin?;
              return AgentFormPage(agent: agent);
            },
          ),
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
                  path: 'properties/edit',
                  name: 'PropertyFormPageEdit',
                  builder: (context, state) {
                    final pmId = state.pathParameters['pmId']!;
                    final property = state.extra as PropertyAdmin?;
                    return PropertyFormPage(pmId: pmId, property: property);
                  }),
              // Create new Building for a Property
              GoRoute(
                path: 'properties/:propertyId/buildings/new',
                name: 'BuildingFormPageNew',
                builder: (context, state) {
                  final pmId = state.pathParameters['pmId']!;
                  final propertyId = state.pathParameters['propertyId']!;
                  return BuildingFormPage(pmId: pmId, propertyId: propertyId);
                },
              ),
              // Edit existing Building for a Property
              GoRoute(
                path: 'properties/:propertyId/buildings/edit',
                name: 'BuildingFormPageEdit',
                builder: (context, state) {
                  final pmId = state.pathParameters['pmId']!;
                  final propertyId = state.pathParameters['propertyId']!;
                  final building = state.extra as BuildingAdmin?;
                  return BuildingFormPage(
                      pmId: pmId, propertyId: propertyId, building: building);
                },
              ),
              // Create new Unit for a Building
              GoRoute(
                path: 'properties/:propertyId/buildings/:buildingId/units/new',
                name: 'UnitFormPageNew',
                builder: (context, state) {
                  final pmId = state.pathParameters['pmId']!;
                  final propertyId = state.pathParameters['propertyId']!;
                  final buildingId = state.pathParameters['buildingId']!;
                  return UnitFormPage(
                      pmId: pmId, propertyId: propertyId, buildingId: buildingId);
                },
              ),
              // Edit existing Unit for a Building
              GoRoute(
                path: 'properties/:propertyId/buildings/:buildingId/units/edit',
                name: 'UnitFormPageEdit',
                builder: (context, state) {
                  final pmId = state.pathParameters['pmId']!;
                  final propertyId = state.pathParameters['propertyId']!;
                  final buildingId = state.pathParameters['buildingId']!;
                  final unit = state.extra as UnitAdmin?;
                  return UnitFormPage(
                      pmId: pmId,
                      propertyId: propertyId,
                      buildingId: buildingId,
                      unit: unit);
                },
              ),
              // Create new Dumpster for a Property
              GoRoute(
                path: 'properties/:propertyId/dumpsters/new',
                name: 'DumpsterFormPageNew',
                builder: (context, state) {
                  final pmId = state.pathParameters['pmId']!;
                  final propertyId = state.pathParameters['propertyId']!;
                  return DumpsterFormPage(pmId: pmId, propertyId: propertyId);
                },
              ),
              // Edit existing Dumpster for a Property
              GoRoute(
                path: 'properties/:propertyId/dumpsters/edit',
                name: 'DumpsterFormPageEdit',
                builder: (context, state) {
                  final pmId = state.pathParameters['pmId']!;
                  final propertyId = state.pathParameters['propertyId']!;
                  final dumpster = state.extra as DumpsterAdmin?;
                  return DumpsterFormPage(
                      pmId: pmId, propertyId: propertyId, dumpster: dumpster);
                },
              ),
              // Create new Job Definition for a Property
              GoRoute(
                path: 'properties/:propertyId/job-definitions/new',
                name: 'JobDefinitionFormPageNew',
                builder: (context, state) {
                  final pmId = state.pathParameters['pmId']!;
                  final propertyId = state.pathParameters['propertyId']!;
                  return JobDefinitionFormPage(
                      pmId: pmId, propertyId: propertyId);
                },
              ),
              // Edit existing Job Definition for a Property
              GoRoute(
                path: 'properties/:propertyId/job-definitions/edit',
                name: 'JobDefinitionFormPageEdit',
                builder: (context, state) {
                  final pmId = state.pathParameters['pmId']!;
                  final propertyId = state.pathParameters['propertyId']!;
                  final jobDefinition = state.extra as JobDefinitionAdmin?;
                  return JobDefinitionFormPage(
                      pmId: pmId,
                      propertyId: propertyId,
                      jobDefinition: jobDefinition);
                },
              ),
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