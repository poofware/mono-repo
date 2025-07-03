// worker-app/lib/features/account/presentation/pages/stripe_connect_in_progress_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/routing/router.dart';
import '../../providers/worker_account_deep_links_provider.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations


class StripeConnectInProgressPage extends ConsumerStatefulWidget {
  const StripeConnectInProgressPage({super.key});

  @override
  ConsumerState<StripeConnectInProgressPage> createState() =>
      _StripeConnectInProgressPageState();
}

class _StripeConnectInProgressPageState
    extends ConsumerState<StripeConnectInProgressPage> {
  bool _isLoading = false;

  Future<void> _handleCheckStatus() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final config = PoofWorkerFlavorConfig.instance;
      final router = GoRouter.of(context);
      if (config.testMode) {
        // Await the push to handle back navigation correctly.
        await router.pushNamed(AppRouteNames.checkrPage);
      } else {
        // Normal mode => call the "force check" method
        await ref
            .read(workerAccountDeepLinkHandlerProvider)
            .forceCheckStripeConnectReturn(router);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                Text(
                  appLocalizations.stripeConnectInProgressPageMessage,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  appLocalizations.stripeConnectInProgressPageCheckStatusPrompt,
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                WelcomeButton(
                  text: appLocalizations.stripeConnectInProgressPageCheckAgainButton,
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _handleCheckStatus,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

