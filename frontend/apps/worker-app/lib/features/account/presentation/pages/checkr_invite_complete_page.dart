import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations


import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';

/// Brief celebratory page shown right after the candidate finishes
/// the Checkr invitation flow.
class CheckrInviteCompletePage extends ConsumerWidget {
  const CheckrInviteCompletePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated green check‑mark
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, size: 80, color: Colors.green)
                        .animate()
                        .scale(
                          begin: Offset.zero,
                          end: const Offset(1, 1),
                          curve: Curves.easeOutBack,
                          duration: 600.ms,
                        )
                        .fadeIn(duration: 600.ms),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    appLocalizations.checkrInviteCompletePageTitle,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appLocalizations.checkrInviteCompletePageMessage,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  WelcomeButton(
                    text: appLocalizations.checkrInviteCompletePageContinueButton,
                    onPressed: () => context.goNamed('CheckrOutcomePage'),
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

