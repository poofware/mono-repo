// worker-app/lib/core/auth/auth_controller.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/providers/app_state_provider.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/core/providers/network_status_provider.dart';
import 'package:poof_worker/features/jobs/providers/providers.dart';
import 'package:poof_worker/features/earnings/providers/providers.dart';
import 'package:poof_worker/features/account/providers/providers.dart';
import 'package:poof_worker/features/account/data/models/worker.dart';
import 'package:poof_worker/core/providers/ui_messaging_provider.dart';
import 'package:poof_worker/core/providers/welcome_video_provider.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/core/utils/location_permissions.dart' as locperm;
import 'package:poof_worker/core/providers/initial_setup_providers.dart';

class AuthController {
  final Ref _ref;
  late final SessionManager _sessionManager;

  AuthController(this._ref) {
    final repo = _ref.read(workerAuthRepositoryProvider);

    _sessionManager = SessionManager(
      repo,
      onLoginStateChanged: (loggedIn) =>
          _ref.read(appStateProvider.notifier).setLoggedIn(loggedIn),
    );

    // Auto-retry refresh when connectivity returns
    _ref.listen<NetworkStatus>(networkStatusProvider, (prev, next) {
      if (prev == NetworkStatus.offline && next == NetworkStatus.online) {
        _sessionManager.tryReconnect();
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  //  PRIVATE HELPERS
  // ─────────────────────────────────────────────────────────────────────

  /// Determines the correct route based on the worker's state and performs
  /// a one-time navigation using the provided GoRouter instance.
  void _navigateToNextStep(GoRouter router) {
    // Pause the welcome video as we are moving into the authenticated app.
    final videoController = _ref.read(welcomeVideoControllerProvider);
    if (videoController != null && videoController.value.isPlaying) {
      videoController.pause();
    }
    final worker = _ref.read(workerStateNotifierProvider).worker;
    if (worker == null) return; // Should not happen if called correctly

    final logger = _ref.read(appLoggerProvider);
    logger.d(
      'Navigating to next step based on worker state: ${worker.accountStatus}, ${worker.setupProgress}',
    );
    switch (worker.accountStatus) {
      case AccountStatusType.incomplete:
        switch (worker.setupProgress) {
          case SetupProgressType.awaitingPersonalInfo:
            router.goNamed(AppRouteNames.addressInfoPage);
            break;
          case SetupProgressType.idVerify:
            if (worker.onWaitlist) {
              router.goNamed(AppRouteNames.waitlistPage);
              return;
            }
            router.goNamed(AppRouteNames.stripeIdvPage);
            break;
          case SetupProgressType.achPaymentAccountSetup:
            router.goNamed(AppRouteNames.stripeConnectPage);
            break;
          case SetupProgressType.backgroundCheck:
            router.goNamed(AppRouteNames.checkrPage);
            break;
          case SetupProgressType.done:
            router.goNamed(AppRouteNames.mainTab);
            break;
        }
        break;
      case AccountStatusType.backgroundCheckPending:
        router.goNamed(AppRouteNames.checkrOutcomePage);
        break;
      case AccountStatusType.active:
        router.goNamed(AppRouteNames.mainTab);
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  PUBLIC API
  // ─────────────────────────────────────────────────────────────────────

  /// Signs the user in, fetches necessary data, and navigates to the correct screen.
  Future<void> signIn<T extends JsonSerializable>(
    T creds,
    GoRouter router,
  ) async {
    await _sessionManager.signIn(creds);

    final worker = _ref.read(workerStateNotifierProvider).worker;
    // Gate both platforms: if account is active and permission missing, show
    // the disclosure first, then resume sign-in flow.
    if (worker != null &&
        worker.accountStatus == AccountStatusType.active &&
        !await locperm.hasLocationPermission()) {
      await router.pushNamed(AppRouteNames.locationDisclosurePage);
    }

    // Navigate ASAP to let heavy UI (map) mount while data loads in background.
    _navigateToNextStep(router);

    // Kick off post-login data fetches after navigation to allow pre-rendering.
    if (worker != null && worker.accountStatus == AccountStatusType.active) {
      // ignore: discarded_futures
      Future.wait([
        _ref.read(jobsNotifierProvider.notifier).fetchAllMyJobs(),
        _ref.read(earningsNotifierProvider.notifier).fetchEarningsSummary(),
      ])
          .then((_) {
        final jobsError = _ref.read(jobsNotifierProvider).error;
        final earningsError = _ref.read(earningsNotifierProvider).error;
        final postLoginErrors = <Object>[
          if (jobsError != null) jobsError,
          if (earningsError != null) earningsError,
        ];
        if (postLoginErrors.isNotEmpty) {
          _ref.read(postBootErrorProvider.notifier).state = postLoginErrors;
        }
      })
          .catchError((Object e, StackTrace s) {
        // Surface background fetch errors to the UI messaging provider
        _ref.read(postBootErrorProvider.notifier).state = [e];
      });
    }
  }

  /// Initializes the session on app start and navigates to the correct screen if logged in.
  Future<void> initSession(GoRouter router) async {
    final logger = _ref.read(appLoggerProvider);
    try {
      await _sessionManager.init();

      if (_sessionManager.isLoggedIn) {
        final worker = await _ref
            .read(workerAccountRepositoryProvider)
            .getWorker();

        // Gate both platforms: avoid triggering GPS fix before disclosure when
        // active, then resume session flow after user acknowledges.
        if (worker.accountStatus == AccountStatusType.active &&
            !await locperm.hasLocationPermission()) {
          await router.pushNamed(AppRouteNames.locationDisclosurePage);
        }

        if (worker.accountStatus == AccountStatusType.active) {
          await Future.wait([
            _ref.read(jobsNotifierProvider.notifier).fetchAllMyJobs(),
            _ref
                .read(earningsNotifierProvider.notifier)
                .fetchEarningsSummary(),
          ]);

          final jobsError = _ref.read(jobsNotifierProvider).error;
          final earningsError = _ref.read(earningsNotifierProvider).error;
          final bootErrors = <Object>[
            if (jobsError != null) jobsError,
            if (earningsError != null) earningsError,
          ];
          if (bootErrors.isNotEmpty) {
            _ref.read(postBootErrorProvider.notifier).state = bootErrors;
          }
        }
        // After all data is settled, navigate.
        _navigateToNextStep(router);
      }
    } catch (e, s) {
      // Catch any exception during init, log it, and allow the app to proceed
      // to the welcome screen gracefully.
      logger.e(
        'Failed to initialize session during boot.',
        error: e,
        stackTrace: s,
      );
      // The app state will remain `isLoggedIn: false`, so no navigation is needed.
    }
  }

  Future<void> signOut(bool testMode) async {
    // Ensure global jobs state is reset to OFFLINE
    await _ref.read(jobsNotifierProvider.notifier).goOffline();
    _ref.invalidate(jobsNotifierProvider);
    _ref.invalidate(earningsNotifierProvider); // Clear earnings state
    _ref.read(workerStateNotifierProvider.notifier).clearWorker();

    // Resume the welcome video so it's playing when the user returns to the welcome screen.
    final videoController = _ref.read(welcomeVideoControllerProvider);
    if (videoController != null && !videoController.value.isPlaying) {
      videoController.play();
    }

    if (testMode) {
      _ref.read(appStateProvider.notifier).setLoggedIn(false);
    } else {
      await _sessionManager.signOut();
    }

    // Clear any persisted home-UI state
    _ref.invalidate(lastMapCameraPositionProvider);
    _ref.invalidate(lastSelectedDefinitionIdProvider);
    // Ensure map warm-up overlays are allowed again on next app run
    _ref.read(homeMapMountedProvider.notifier).state = false;
  }

  Future<void> handleAuthLost() async {
    // Go offline and clear all job state
    await _ref.read(jobsNotifierProvider.notifier).goOffline();
    _ref.invalidate(jobsNotifierProvider);
    _ref.invalidate(earningsNotifierProvider); // Clear earnings state
    _ref.read(workerStateNotifierProvider.notifier).clearWorker();

    // Resume the welcome video so it's playing when the user returns to the welcome screen.
    final videoController = _ref.read(welcomeVideoControllerProvider);
    if (videoController != null && !videoController.value.isPlaying) {
      videoController.play();
    }

    // Handle token clearing and update login status
    await _sessionManager.handleAuthLost();

    // Clear any persisted home-UI state
    _ref.invalidate(lastMapCameraPositionProvider);
    _ref.invalidate(lastSelectedDefinitionIdProvider);
    // Ensure map warm-up overlays are allowed again on next app run
    _ref.read(homeMapMountedProvider.notifier).state = false;
  }
}
