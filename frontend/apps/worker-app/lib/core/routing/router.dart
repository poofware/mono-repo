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
import 'package:poof_worker/features/earnings/data/models/models.dart'
    show WeeklyEarnings;

// Our new Signing Out page
import 'package:poof_worker/features/auth/presentation/pages/signing_out_page.dart';
import 'package:poof_worker/features/auth/presentation/pages/session_expired_page.dart';

/// Defines the named routes used throughout the application for navigation.
class AppRouteNames {
  static const String home = 'Home';
  static const String loginPage = 'LoginPage';
  static const String createAccountPage = 'CreateAccountPage';
  static const String phoneVerificationInfoPage = 'PhoneVerificationInfoPage';
  static const String verifyNumberPage = 'VerifyNumberPage';
  static const String addressInfoPage = 'AddressInfoPage';
  static const String vehicleSetupPage = 'VehicleSetupPage';
  static const String totpSignUpPage = 'TotpSignUpPage';
  static const String signupSuccessPage = 'SignupSuccessPage';
  static const String signupExpiredPage = 'SignupExpiredPage';
  static const String totpVerifyPage = 'TotpVerifyPage';
  static const String checkrPage = 'CheckrPage';
  static const String checkrInProgressPage = 'CheckrInProgressPage';
  static const String checkrInviteWebViewPage = 'CheckrInviteWebViewPage';
  static const String checkrInviteCompletePage = 'CheckrInviteCompletePage';
  static const String checkrOutcomePage = 'CheckrOutcomePage';
  static const String stripeIdvPage = 'StripeIdvPage';
  static const String stripeIdvInProgressPage = 'StripeIdvInProgressPage';
  static const String stripeIdvNotCompletePage = 'StripeIdvNotCompletePage';
  static const String stripeConnectPage = 'StripeConnectPage';
  static const String stripeConnectInProgressPage = 'StripeConnectInProgressPage';
  static const String stripeConnectNotCompletePage = 'StripeConnectNotCompletePage';
  static const String mainTab = 'MainTab';
  static const String homePage = 'HomePage';
  static const String acceptedJobsPage = 'AcceptedJobsPage';
  static const String jobMapPage = 'JobMapPage';
  static const String jobInProgressPage = 'JobInProgressPage';
  static const String earningsPage = 'EarningsPage';
  static const String weekEarningsDetailPage = 'WeekEarningsDetailPage';
  static const String settingsPage = 'SettingsPage';
  static const String myProfilePage = 'MyProfilePage';
  static const String signingOutPage = 'SigningOutPage';
  static const String sessionExpiredPage = 'SessionExpiredPage';
}

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
      name: AppRouteNames.home,
      builder: (_, __) => const WelcomePage()),
  AppRoute(
    access: RouteAccess.public,
    path: '/login',
    name: AppRouteNames.loginPage,
    pageBuilder: (context, state) => const CupertinoPage(
      child: LoginPage(),
    ),
  ),
  AppRoute(
      access: RouteAccess.public,
      path: '/create_account',
      name: AppRouteNames.createAccountPage,
      pageBuilder: (context, state) => const CupertinoPage(
            child: CreateAccountPage(),
          )),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/phone_verification_info',
      name: AppRouteNames.phoneVerificationInfoPage,
      pageBuilder: (context, state) {
        final args = state.extra as PhoneVerificationInfoArgs;
        return CupertinoPage(child: PhoneVerificationInfoPage(args: args));
      }),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/verify_number',
      name: AppRouteNames.verifyNumberPage,
      pageBuilder: (context, state) {
        final args = state.extra as VerifyNumberArgs;
        return CupertinoPage(child: VerifyNumberPage(args: args));
      }),
  AppRoute(
      access: RouteAccess.protected,
      path: '/address_info',
      name: AppRouteNames.addressInfoPage,
      builder: (_, __) => const AddressInfoPage()),
  AppRoute(
    access: RouteAccess.protected,
    path: '/vehicle_setup',
    name: AppRouteNames.vehicleSetupPage,
    pageBuilder: (context, state) =>
        const CupertinoPage(child: VehicleSetupPage()),
  ),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/totp_signup',
      name: AppRouteNames.totpSignUpPage,
      pageBuilder: (context, state) =>
          const CupertinoPage(child: TotpSignUpPage())),
  AppRoute(
      access: RouteAccess.public,
      path: '/signup_success',
      name: AppRouteNames.signupSuccessPage,
      pageBuilder: (context, state) =>
          const CupertinoPage(child: SignupSuccessPage())),
  AppRoute(
      access: RouteAccess.public,
      path: '/signup_expired',
      name: AppRouteNames.signupExpiredPage,
      pageBuilder: (context, state) =>
          const CupertinoPage(child: SignupExpiredPage())),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/totp_verify',
      name: AppRouteNames.totpVerifyPage,
      pageBuilder: (_, state) {
        final args = state.extra as TotpVerifyArgs;
        return CupertinoPage(child: TotpVerifyPage(args: args));
      }),
  AppRoute(
      access: RouteAccess.protected,
      path: '/checkr',
      name: AppRouteNames.checkrPage,
      builder: (_, __) => const BackgroundCheckPage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/checkr_in_progress',
      name: AppRouteNames.checkrInProgressPage,
      pageBuilder: (context, state) =>
          const CupertinoPage(child: CheckrInProgressPage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/checkr_invite',
      name: AppRouteNames.checkrInviteWebViewPage,
      pageBuilder: (_, state) {
        final url = state.extra as String;
        return CupertinoPage(
            child: CheckrInviteWebViewPage(invitationUrl: url));
      }),
  AppRoute(
      access: RouteAccess.protected,
      path: '/checkr_invite_complete',
      name: AppRouteNames.checkrInviteCompletePage,
      pageBuilder: (context, state) =>
          const CupertinoPage(child: CheckrInviteCompletePage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/checkr_outcome',
      name: AppRouteNames.checkrOutcomePage,
      builder: (_, __) => const CheckrOutcomePage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_idv',
      name: AppRouteNames.stripeIdvPage,
      builder: (_, __) => const VerifyIdentityPage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_idv_in_progress',
      name: AppRouteNames.stripeIdvInProgressPage,
      pageBuilder: (context, state) =>
          const CupertinoPage(child: StripeIdvInProgressPage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_idv_not_complete',
      name: AppRouteNames.stripeIdvNotCompletePage,
      pageBuilder: (context, state) =>
          const CupertinoPage(child: StripeIdvNotCompletePage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_connect',
      name: AppRouteNames.stripeConnectPage,
      builder: (_, __) => const StripePage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_connect_in_progress',
      name: AppRouteNames.stripeConnectInProgressPage,
      pageBuilder: (context, state) =>
          const CupertinoPage(child: StripeConnectInProgressPage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/stripe_connect_not_complete',
      name: AppRouteNames.stripeConnectNotCompletePage,
      pageBuilder: (context, state) =>
          const CupertinoPage(child: StripeConnectNotCompletePage())),
  AppRoute(
      access: RouteAccess.protected,
      path: '/main',
      name: AppRouteNames.mainTab,
      builder: (_, __) => const MainTabsScreen()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/home',
      name: AppRouteNames.homePage,
      builder: (_, __) => const HomePage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/accepted_jobs',
      name: AppRouteNames.acceptedJobsPage,
      builder: (_, __) => const AcceptedJobsPage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/job_map',
      name: AppRouteNames.jobMapPage,
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
    name: AppRouteNames.jobInProgressPage,
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
      name: AppRouteNames.earningsPage,
      builder: (_, __) => const EarningsPage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/week_earnings_detail',
      name: AppRouteNames.weekEarningsDetailPage,
      builder: (_, state) {
        final week = state.extra as WeeklyEarnings;
        return WeekEarningsDetailPage(week: week);
      }),
  AppRoute(
      access: RouteAccess.protected,
      path: '/settings',
      name: AppRouteNames.settingsPage,
      builder: (_, __) => const SettingsPage()),
  AppRoute(
      access: RouteAccess.protected,
      path: '/my_profile',
      name: AppRouteNames.myProfilePage,
      builder: (_, __) => const MyProfilePage()),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/signing_out',
      name: AppRouteNames.signingOutPage,
      builder: (_, __) => const SigningOutPage()),
  AppRoute(
      access: RouteAccess.unrestricted,
      path: '/session_expired',
      name: AppRouteNames.sessionExpiredPage,
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
    bool? wasLoggedIn; // null until first event arrives
    _sub = stream.listen((appState) {
      final lostAuth = wasLoggedIn == true && !appState.isLoggedIn;
      wasLoggedIn = appState.isLoggedIn;
      if (lostAuth) notifyListeners(); // fire ONLY on login → logout
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
        final routeName = state.topRoute?.name;
        final location = state.topRoute?.path;

        // look up the access flag
        final access = _accessByName[routeName] ??
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
