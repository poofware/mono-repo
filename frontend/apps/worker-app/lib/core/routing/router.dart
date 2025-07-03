// worker-app/lib/core/routing/router.dart

import 'package:flutter/cupertino.dart'; // Import for CupertinoPageRoute
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:poof_worker/core/app_state/app_state_notifier.dart';
import 'package:poof_worker/core/app_state/app_state.dart';

// Pages
import 'package:poof_worker/features/auth/presentation/pages/login_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/welcome_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/create_account_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/totp_verify_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/verify_number_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/vehicle_setup_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/address_info_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/totp_signup_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/phone_verification_info_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/signup_success_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/signup_expired_page.dart';


// Checkr / Stripe / Account
import 'package:poof_worker/features/account/presentation/pages/checkr_page.dart';
import 'package:poof_worker/features/account/presentation/pages/checkr_in_progress_page.dart';
import 'package:poof_worker/features/account/presentation/pages/checkr_invite_webview_page.dart';
import 'package:poof_worker/features/account/presentation/pages/checkr_outcome_page.dart';
import 'package:poof_worker/features/account/presentation/pages/checkr_invite_complete_page.dart';
import 'package:poof_worker/features/account/presentation/pages/stripe_connect_page.dart';
import 'package:poof_worker/features/account/presentation/pages/stripe_connect_in_progress_page.dart';
import 'package:poof_worker/features/account/presentation/pages/stripe_connect_not_complete_page.dart';
import 'package:poof_worker/features/account/presentation/pages/stripe_idv_page.dart';
import 'package:poof_worker/features/account/presentation/pages/stripe_idv_in_progress_page.dart';
import 'package:poof_worker/features/account/presentation/pages/stripe_idv_not_complete_page.dart';
import 'package:poof_worker/features/account/presentation/pages/settings_page.dart';
import 'package:poof_worker/features/account/presentation/pages/my_profile_page.dart';

// Jobs
import 'package:poof_worker/features/jobs/presentation/pages/main_tabs_page.dart';
import 'package:poof_worker/features/jobs/presentation/pages/home_page.dart';
import 'package:poof_worker/features/jobs/presentation/pages/accepted_jobs_page.dart';
import 'package:poof_worker/features/jobs/presentation/pages/job_in_progress_page.dart';
import 'package:poof_worker/features/jobs/presentation/pages/job_map_page.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';

// Earnings
import 'package:poof_worker/features/earnings/presentation/pages/earnings_page.dart';
import 'package:poof_worker/features/earnings/presentation/pages/weekly_earnings_page.dart';
import 'package:poof_worker/features/earnings/data/models/models.dart' show WeeklyEarnings;


// Our new Signing Out page
import 'package:poof_worker/features/auth/presentation/pages/signing_out_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/session_expired_page.dart';

enum RouteAccess {
  public,
  protected,
  unrestricted,
}

class AppRoute extends GoRoute {
  final RouteAccess access;
  AppRoute(
      {required this.access,
      required super.path,
      required super.name,
      super.builder,
      super.pageBuilder,
      super.routes});
}

final List<AppRoute> _appRoutes = [
  // ... other routes are unchanged ...
  AppRoute(
      access: RouteAccess.public,
      path: '/',
      name: 'Home',
      builder: (_, __) => const WelcomePage()),
  AppRoute(
    access: RouteAccess.public,
    path: '/login',
    name: 'LoginPage',
    pageBuilder: (context, state) => const CupertinoPage(
      child: LoginPage(),
    ),
  ),
  AppRoute(
      access: RouteAccess.public,
      path: '/create_account',
      name: 'CreateAccountPage',
      pageBuilder: (context, state) => const CupertinoPage(
            child: CreateAccountPage(),
          )),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/phone_verification_info',
      name: 'PhoneVerificationInfoPage',
      pageBuilder: (context, state) {
        final args = state.extra as PhoneVerificationInfoArgs;
        return CupertinoPage(child: PhoneVerificationInfoPage(args: args));
      }),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/verify_number',
      name: 'VerifyNumberPage',
      pageBuilder: (context, state) {
        final args = state.extra as VerifyNumberArgs;
        return CupertinoPage(child: VerifyNumberPage(args: args));
      }),
  AppRoute(
      access: RouteAccess.protected,
      path: '/address_info',
      name: 'AddressInfoPage',
      builder: (_, __) => const AddressInfoPage()),
  AppRoute(
    access: RouteAccess.protected,
    path: '/vehicle_setup',
    name: 'VehicleSetupPage',
    pageBuilder: (context, state) =>
        const CupertinoPage(child: VehicleSetupPage()),
  ),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/totp_signup',
      name: 'TotpSignUpPage',
      pageBuilder: (context, state) =>
          const CupertinoPage(child: TotpSignUpPage())),
  AppRoute(
      access: RouteAccess.public,
      path: '/signup_success',
      name: 'SignupSuccessPage',
      pageBuilder: (context, state) =>
          const CupertinoPage(child: SignupSuccessPage())),
  AppRoute(
      access: RouteAccess.public,
      path: '/signup_expired',
      name: 'SignupExpiredPage',
      pageBuilder: (context, state) =>
          const CupertinoPage(child: SignupExpiredPage())),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/totp_verify',
      name: 'TotpVerifyPage',
      pageBuilder: (_, state) {
        final args = state.extra as TotpVerifyArgs;
        return CupertinoPage(child: TotpVerifyPage(args: args));
      }),
  AppRoute(
      access: RouteAccess.protected,
      path: '/checkr',
      name: 'CheckrPage',
      builder: (_, __) => const BackgroundCheckPage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/checkr_in_progress',
      name: 'CheckrInProgressPage',
      pageBuilder: (context, state) =>
          const CupertinoPage(child: CheckrInProgressPage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/checkr_invite',
      name: 'CheckrInviteWebViewPage',
      pageBuilder: (_, state) {
        final url = state.extra as String;
        return CupertinoPage(
            child: CheckrInviteWebViewPage(invitationUrl: url));
      }),
  AppRoute(
      access: RouteAccess.protected,
      path: '/checkr_invite_complete',
      name: 'CheckrInviteCompletePage',
      pageBuilder: (context, state) =>
          const CupertinoPage(child: CheckrInviteCompletePage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/checkr_outcome',
      name: 'CheckrOutcomePage',
      builder: (_, __) => const CheckrOutcomePage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_idv',
      name: 'StripeIdvPage',
      builder: (_, __) => const VerifyIdentityPage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_idv_in_progress',
      name: 'StripeIdvInProgressPage',
      pageBuilder: (context, state) =>
          const CupertinoPage(child: StripeIdvInProgressPage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_idv_not_complete',
      name: 'StripeIdvNotCompletePage',
      pageBuilder: (context, state) =>
          const CupertinoPage(child: StripeIdvNotCompletePage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_connect',
      name: 'StripeConnectPage',
      builder: (_, __) => const StripePage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_connect_in_progress',
      name: 'StripeConnectInProgressPage',
      pageBuilder: (context, state) =>
          const CupertinoPage(child: StripeConnectInProgressPage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_connect_not_complete',
      name: 'StripeConnectNotCompletePage',
      pageBuilder: (context, state) =>
          const CupertinoPage(child: StripeConnectNotCompletePage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/main',
      name: 'MainTab',
      builder: (_, __) => const MainTabsScreen()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/home',
      name: 'HomePage',
      builder: (_, __) => const HomePage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/accepted_jobs',
      name: 'AcceptedJobsPage',
      builder: (_, __) => const AcceptedJobsPage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/job_map',
      name: 'JobMapPage',
      pageBuilder: (_, state) {
        final job = state.extra as JobInstance;
        return CustomTransitionPage<void>(
            key: state.pageKey,
            child: JobMapPage(job: job),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(1.0, 0.0), end: Offset.zero)
                      .animate(animation),
                  child: child);
            });
      }),
  AppRoute(
    access: RouteAccess.protected,
    path: '/job_in_progress',
    name: 'JobInProgressPage',
    builder: (_, state) {
      final job = state.extra as JobInstance;
      final coldMap = JobMapPage(
        key: GlobalObjectKey('map-${job.instanceId}'),
        job: job,
        isForWarmup: false,
        buildAsScaffold: false,
      );

      return JobInProgressPage(
        job: job,
        preWarmedMap: coldMap,
      );
    },
  ),
  AppRoute(
      access: RouteAccess.protected,
      path: '/earnings',
      name: 'EarningsPage',
      builder: (_, __) => const EarningsPage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/week_earnings_detail',
      name: 'WeekEarningsDetailPage',
      builder: (_, state) {
        final week = state.extra as WeeklyEarnings;
        return WeekEarningsDetailPage(week: week);
      }),
  AppRoute(
      access: RouteAccess.protected,
      path: '/settings',
      name: 'SettingsPage',
      builder: (_, __) => const SettingsPage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/my_profile',
      name: 'MyProfilePage',
      builder: (_, __) => const MyProfilePage()),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/signing_out',
      name: 'SigningOutPage',
      builder: (_, __) => const SigningOutPage()),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/session_expired',
      name: 'SessionExpiredPage',
      builder: (_, __) => const SessionExpiredPage()),
];

// ... rest of the file is unchanged ...
final Map<String, RouteAccess> _accessByName = {
  for (final r in _appRoutes) r.name!: r.access
};
final Map<String, RouteAccess> _accessByPath = {
  for (final r in _appRoutes) r.path: r.access
};

class AuthLostRefresh extends ChangeNotifier {
  AuthLostRefresh(Stream<AppStateData> stream) {
    bool? wasLoggedIn;              // null until first event arrives
    _sub = stream.listen((appState) {
      final lostAuth = wasLoggedIn == true && !appState.isLoggedIn;
      wasLoggedIn  = appState.isLoggedIn;
      if (lostAuth) notifyListeners();  // fire ONLY on login → logout
    });
  }

  late final StreamSubscription<AppStateData> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

GoRouter createRouter(AppStateNotifier appStateNotifier) {
  final router = GoRouter(
      debugLogDiagnostics: true,
      refreshListenable: AuthLostRefresh(appStateNotifier.stream),
      redirect: (context, state) {
        final loggedIn = appStateNotifier.isLoggedIn;

        // deepest match
        // consider returning this location instead of null
        final routeName  = state.topRoute?.name;
        final location   = state.topRoute?.path;

        // look up the access flag
        final access     = _accessByName[routeName] ??
                           _accessByPath[location] ??
                           RouteAccess.protected;

        debugPrint(
            'Redirecting to $location (name: ${routeName ?? 'unknown'}, access: $access, loggedIn: $loggedIn)');

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
      routes: _appRoutes);

  router.routerDelegate.addListener(() {
    // Runs after every push/go/pop/replace, etc.
    final matches = router.routerDelegate.currentConfiguration.matches;
    debugPrint(
        'Stack changed → ${matches.map((m) => m.matchedLocation).toList()}');
  });

  return router;
}
