// worker-app/lib/features/account/utils/stripe_utils.dart
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/presentation/utils/url_launcher_utils.dart';
import '../data/repositories/worker_account_repository.dart';

/// Starts the Stripe Connect flow.
/// Returns `true` if the URL was successfully launched.
Future<bool> startStripeConnectFlow(
    {required GoRouter router, required WorkerAccountRepository repo}) async {
  final flowUrl = await repo.getStripeConnectFlowUrl();
  final success = await tryLaunchUrl(flowUrl);
  if (success) {
    router.pushNamed('StripeConnectInProgressPage');
  }
  return success;
}

/// Starts the Stripe Identity Verification flow.
/// Returns `true` if the URL was successfully launched.
Future<bool> startStripeIdentityFlow(
    {required GoRouter router, required WorkerAccountRepository repo}) async {
  final idvUrl = await repo.getStripeIdentityFlowUrl();
  final success = await tryLaunchUrl(idvUrl);
  if (success) {
    router.pushNamed('StripeIdvInProgressPage');
  }
  return success;
}
