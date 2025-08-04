import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/features/account/providers/worker_account_repository_provider.dart';
import 'package:poof_worker/features/account/utils/stripe_utils.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';

/// A page that briefly informs the user that they did NOT finish Stripe Connect
/// and that we will automatically re-launch the connect flow now.
class StripeConnectNotCompletePage extends ConsumerStatefulWidget {
  const StripeConnectNotCompletePage({super.key});

  @override
  ConsumerState<StripeConnectNotCompletePage> createState() =>
      _StripeConnectNotCompletePageState();
}

class _StripeConnectNotCompletePageState
    extends ConsumerState<StripeConnectNotCompletePage> {
  bool _hasLaunched = false;

  @override
  void initState() {
    super.initState();
    // We'll do a short delay or do it right away
    WidgetsBinding.instance.addPostFrameCallback((_) => _launchFlow());
  }

  Future<void> _launchFlow() async {
    if (_hasLaunched) return; // guard
    _hasLaunched = true;

    // Capture the context-dependent objects BEFORE the async gap.
    final router = GoRouter.of(context);
    final BuildContext capturedContext = context;
    final repo = ref.read(workerAccountRepositoryProvider);

    // Show message for a couple of seconds, purely optional
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    // Now re-launch the connect flow
    try {
      final success = await startStripeConnectFlow(router: router, repo: repo);
      if (!success) {
        if (!capturedContext.mounted) return;
        showAppSnackBar(
          capturedContext,
          Text(AppLocalizations.of(capturedContext).urlLauncherCannotLaunch),
        );
      }
    } on ApiException catch (e) {
      if (!capturedContext.mounted) return;
      showAppSnackBar(
        capturedContext,
        Text(userFacingMessage(capturedContext, e)),
      );
    } catch (e) {
      if (!capturedContext.mounted) return;
      showAppSnackBar(
        capturedContext,
        Text(
          AppLocalizations.of(
            capturedContext,
          ).loginUnexpectedError(e.toString()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                        Icons.sync_problem_outlined,
                        size: 80,
                        color: Colors.orange.shade700,
                      )
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .scale(delay: 200.ms, curve: Curves.easeOutBack),
                  const SizedBox(height: 24),
                  Text(
                    appLocalizations.stripeConnectNotCompletePageTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    appLocalizations.stripeConnectNotCompletePageMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
