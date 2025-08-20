import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/core/providers/app_providers.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_page_wrapper.dart';

/// A simple "Signing Out..." page that shows a spinner
/// for ~2 seconds, then redirects to the welcome screen.
/// In real usage, you'd call your pmAuthRepository.signOut().
class SigningOutPage extends ConsumerStatefulWidget {
  const SigningOutPage({super.key});

  @override
  ConsumerState<SigningOutPage> createState() => _SigningOutPageState();
}

class _SigningOutPageState extends ConsumerState<SigningOutPage> {
  @override
  void initState() {
    super.initState();
    // Use a microtask to ensure the first frame builds before we start async work.
    Future.microtask(_performSignOut);
  }

  Future<void> _performSignOut() async {
    final start = DateTime.now();

    final config = PoofPMFlavorConfig.instance;
    // If testMode is false => real sign out
    if (!config.testMode) {
      await ref.read(authControllerProvider).signOut();
    } else {
      // Test mode => skip real calls, do a short wait
      await Future.delayed(const Duration(milliseconds: 500));
      // Then just set loggedIn = false
      ref.read(appStateProvider.notifier).setLoggedIn(false);
    }

    // Ensure at least 2 seconds for UI so the user can see the message.
    final elapsed = DateTime.now().difference(start);
    if (elapsed < const Duration(seconds: 2)) {
      await Future.delayed(const Duration(seconds: 2) - elapsed);
    }

    if (mounted) {
      // Directly navigate. GoRouter will handle replacing the page.
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return AuthPageWrapper(
      showBackButton: false, // No back button on a final screen like this.
      // MODIFICATION: Replaced boilerplate Container with AuthFormCard.
      child: AuthFormCard(
        // Override padding for a more centered, spacious look on this info page.
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Signing Out',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
            const SizedBox(height: 32),
            Text(
              'Please wait a moment...',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}