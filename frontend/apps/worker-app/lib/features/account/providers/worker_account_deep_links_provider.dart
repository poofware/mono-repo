// lib/features/account/providers/worker_account_deep_links_provider.dart

import 'dart:async'; // Import 'dart:async' for unawaited

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';
import 'package:poof_worker/features/account/data/models/worker.dart';
import 'package:poof_worker/features/account/data/repositories/worker_account_repository.dart';
import 'package:poof_worker/features/account/providers/worker_state_notifier_provider.dart';

import 'package:poof_worker/core/deeplinks/deep_link_handler.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'worker_account_repository_provider.dart';

/// Exposes an instance of the [WorkerAccountDeepLinkHandler].
final workerAccountDeepLinkHandlerProvider =
    Provider<WorkerAccountDeepLinkHandler>((ref) {
  final repo = ref.read(workerAccountRepositoryProvider);
  final logger = ref.read(appLoggerProvider);
  // Pass the ref to the handler
  return WorkerAccountDeepLinkHandler(ref, repo, logger);
});

/// A [DeepLinkHandler] specialized for any “/poofworker/...” links
/// that revolve around the Worker’s Stripe or Checkr flows.
class WorkerAccountDeepLinkHandler implements DeepLinkHandler {
  // Store the ref
  WorkerAccountDeepLinkHandler(this._ref, this._repo, this._logger);

  final Ref _ref;
  final WorkerAccountRepository _repo;
  final dynamic _logger;

  // ---------------------------
  // DeepLinkHandler interface
  // ---------------------------

  @override
  bool canHandle(Uri uri) {
    // We only handle paths that start with /poofworker
    return uri.path.startsWith('/poofworker');
  }

  @override
  bool requiresAuth(Uri uri) {
    // If it's "stripe-connect-return" or "stripe-identity-return", etc.
    // we presumably need auth,
    // but if there's some public link for an open info page, you can choose differently.
    final path = uri.path;
    if (path == '/poofworker/stripe-connect-return' ||
        path == '/poofworker/stripe-connect-refresh' ||
        path == '/poofworker/stripe-identity-return') {
      return true; // Protected
    }
    // fallback
    return false;
  }

  @override
  Future<void> handle(Uri uri, GoRouter router) async {
    _logger.d('WorkerAccountDeepLinkHandler: handling $uri');

    switch (uri.path) {
      case '/poofworker/stripe-connect-return':
        await _handleStripeConnectReturn(router);
        break;
      case '/poofworker/stripe-connect-refresh':
        await _handleStripeConnectRefresh(router);
        break;
      case '/poofworker/stripe-identity-return':
        await _handleStripeIdentityReturn(router);
        break;
      default:
        _logger.e('WorkerAccountDeepLinkHandler: unhandled path: ${uri.path}');
        break;
    }
  }

  // -----------------------------------------------------------------------
  // "force" public methods remain, to be used in the rest of the code
  // if some UI wants to forcibly re-check statuses.
  // These skip the coordinator flow and do the steps directly.
  // -----------------------------------------------------------------------
  Future<void> forceCheckStripeConnectReturn(GoRouter router) {
    return _handleStripeConnectReturn(router);
  }

  Future<void> forceCheckStripeIdentityReturn(GoRouter router) {
    return _handleStripeIdentityReturn(router);
  }

  // -----------------------------------------------------------------------
  // Private link handlers (internal)
  // -----------------------------------------------------------------------

  /// 1) Check Stripe Connect status. If complete => push /checkr
  ///    If not => push "not complete" => user sees a message, then re-invokes the flow
  Future<void> _handleStripeConnectReturn(GoRouter router) async {
    final worker = _ref.read(workerStateNotifierProvider).worker;
    // If the worker's setup is already past the ACH step, this link is stale. Ignore it.
    if (worker != null &&
        worker.setupProgress != SetupProgressType.achPaymentAccountSetup) {
      _logger.i(
          'Ignoring Stripe Connect return link because setup progress is at: ${worker.setupProgress}');
      return;
    }

    try {
      final status = await _repo.getStripeConnectFlowStatus();
      if (status.toLowerCase() == 'complete') {
        unawaited(_repo.getWorker());
        router.pushNamed(AppRouteNames.checkrPage);
      } else {
        router.pushNamed(AppRouteNames.stripeConnectNotCompletePage);
      }
    } catch (e, s) {
      _logger.e('Error handling stripe-connect-return: $e\n$s');
      router.pushNamed(AppRouteNames.stripeConnectNotCompletePage);
    }
  }

  /// 2) If the refresh handler is hit, we show the "Not Complete" page
  ///    and then re-invoke the connect flow in that page’s logic.
  Future<void> _handleStripeConnectRefresh(GoRouter router) async {
    router.pushNamed(AppRouteNames.stripeConnectNotCompletePage);
  }

  /// 3) Check Stripe ID verification. If complete => push /stripe_connect
  ///    If not => push "IDV not complete" => re-invokes the flow
  Future<void> _handleStripeIdentityReturn(GoRouter router) async {
    final worker = _ref.read(workerStateNotifierProvider).worker;
    // If the worker's setup is already past the IDV step, this link is stale. Ignore it.
    if (worker != null && worker.setupProgress != SetupProgressType.idVerify) {
      _logger.i(
          'Ignoring Stripe Identity return link because setup progress is already at: ${worker.setupProgress}');
      return;
    }

    try {
      final status = await _repo.getStripeIdentityFlowStatus();
      if (status.toLowerCase() == 'complete') {
        unawaited(_repo.getWorker());
        router.pushNamed(AppRouteNames.stripeConnectPage);
      } else {
        router.pushNamed(AppRouteNames.stripeIdvNotCompletePage);
      }
    } catch (e, s) {
      _logger.e('Error handling stripe-identity-return: $e\n$s');
      router.pushNamed(AppRouteNames.stripeIdvNotCompletePage);
    }
  }
}
