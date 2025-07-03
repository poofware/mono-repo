// worker-app/lib/features/auth/presentation/pages/signup_success_page.dart
// NEW FILE
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

class SignupSuccessPage extends StatelessWidget {
  const SignupSuccessPage({super.key});

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
                      color: Colors.green.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_outline,
                        size: 80, color: Colors.green),
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
                    appLocalizations.signupSuccessTitle,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appLocalizations.signupSuccessMessage,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  WelcomeButton(
                    text: appLocalizations.signupSuccessButton,
                    onPressed: () => context.goNamed(AppRouteNames.loginPage),
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

