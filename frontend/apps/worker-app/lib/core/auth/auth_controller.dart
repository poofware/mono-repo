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

    switch (worker.accountStatus) {
      case AccountStatusType.incomplete:
        switch (worker.setupProgress) {
          case SetupProgressType.awaitingPersonalInfo:
            router.goNamed('AddressInfoPage');
            break;
          case SetupProgressType.idVerify:
            router.goNamed('StripeIdvPage');
            break;
          case SetupProgressType.achPaymentAccountSetup:
            router.goNamed('StripeConnectPage');
            break;
          case SetupProgressType.backgroundCheck:
            router.goNamed('CheckrPage');
            break;
          case SetupProgressType.done:
            router.goNamed('MainTab');
            break;
        }
        break;
      case AccountStatusType.backgroundCheckPending:
        router.goNamed('CheckrOutcomePage');
        break;
      case AccountStatusType.active:
        router.goNamed('MainTab');
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  //  PUBLIC API
  // ─────────────────────────────────────────────────────────────────────

  /// Signs the user in, fetches necessary data, and navigates to the correct screen.
  Future<void> signIn<T extends JsonSerializable>(T creds, GoRouter router) async {
    await _sessionManager.signIn(creds);

    final worker = _ref.read(workerStateNotifierProvider).worker;
    if (worker != null && worker.accountStatus == AccountStatusType.active) {
      await Future.wait([
        _ref.read(jobsNotifierProvider.notifier).fetchAllMyJobs(),
        _ref.read(earningsNotifierProvider.notifier).fetchEarningsSummary(),
      ]);

      final jobsError = _ref.read(jobsNotifierProvider).error;
      final earningsError = _ref.read(earningsNotifierProvider).error;
      final postLoginErrors = <Object>[
        if (jobsError != null) jobsError,
        if (earningsError != null) earningsError,
      ];
      if (postLoginErrors.isNotEmpty) {
        _ref.read(postBootErrorProvider.notifier).state = postLoginErrors;
      }
    }
    
    // After all data is settled, navigate.
    _navigateToNextStep(router);
  }

  /// Initializes the session on app start and navigates to the correct screen if logged in.
  Future<void> initSession(GoRouter router) async {
    final logger = _ref.read(appLoggerProvider);
    try {
      await _sessionManager.init();
      
      if (_sessionManager.isLoggedIn) {
        final worker = await _ref.read(workerAccountRepositoryProvider).getWorker();
        
        if (worker.accountStatus == AccountStatusType.active) {
          await Future.wait([
            _ref.read(jobsNotifierProvider.notifier).fetchAllMyJobs(),
            _ref.read(earningsNotifierProvider.notifier).fetchEarningsSummary(),
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
      logger.e('Failed to initialize session during boot.', error: e, stackTrace: s);
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
  }
}
