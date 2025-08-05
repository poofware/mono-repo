// frontend/apps/worker-app/lib/features/auth/presentation/pages/waitlist_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';

import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/features/account/providers/providers.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

class WaitlistPage extends ConsumerStatefulWidget {
  const WaitlistPage({super.key});

  @override
  ConsumerState<WaitlistPage> createState() => _WaitlistPageState();
}

class _WaitlistPageState extends ConsumerState<WaitlistPage> {
  bool _checking = false;

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    final repo = ref.read(workerAccountRepositoryProvider);
    final app = AppLocalizations.of(context);
    try {
      final worker = await repo.getWorker();
      if (!worker.onWaitlist) {
        if (mounted) {
          context.goNamed(AppRouteNames.stripeIdvPage);
        }
      } else {
        if (mounted) {
          showAppSnackBar(
            context,
            Text(app.waitlistStillWaitingMessage),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          Text(
            e is ApiException
                ? userFacingMessage(context, e)
                : e.toString(),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.hourglass_empty,
                        size: 80, color: theme.colorScheme.primary),
                  )
                      .animate()
                      .scale(
                        begin: Offset.zero,
                        end: const Offset(1, 1),
                        curve: Curves.easeOutBack,
                        duration: 600.ms,
                      )
                      .fadeIn(duration: 600.ms),
                  const SizedBox(height: 32),
                  Text(
                    app.waitlistPageTitle,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    app.waitlistPageMessage,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  WelcomeButton(
                    text: app.waitlistPageCheckStatusButton,
                    isLoading: _checking,
                    onPressed: _checking ? null : _checkStatus,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
