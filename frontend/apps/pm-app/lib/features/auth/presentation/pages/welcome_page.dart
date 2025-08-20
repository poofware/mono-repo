import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_page_wrapper.dart';

/// The main landing and login page, styled after the Stripe sign-in page.
/// It serves as the primary authentication entry point where the user can
/// either sign in or navigate to the account creation flow.
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  final _emailController = TextEditingController();

  void _onContinue() {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    // Navigate to the next step, passing the email.
    context.push('/login-verify-code', extra: email);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // The security message is now the only content passed to the
    // AuthPageWrapper's footer, keeping it separate from the main card.
    final pageFooter = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline,
              size: 16, color: Colors.black.withOpacity(0.8)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'If you use two-step authentication, keep your backup codes in a secure place. They can help you recover access to your account if you get locked out.',
              style: textTheme.bodySmall
                  ?.copyWith(color: Colors.black.withOpacity(0.8)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );

    // MODIFICATION: The "Create account" link is now the footer for the AuthFormCard.
    final cardFooter = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("New to Poof? ", style: textTheme.bodyMedium),
        GestureDetector(
          onTap: () => context.push('/create_account'),
          child: Text(
            'Create account',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );

    return AuthPageWrapper(
      footer: pageFooter,
      // MODIFICATION: Replaced boilerplate Container with AuthFormCard.
      child: AuthFormCard(
        footer: cardFooter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign in to your account',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 24),

            // Email Field
            Text('Email',
                style:
                    textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 20),

            // Sign In Button
            ElevatedButton(
              onPressed: _onContinue,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Continue',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 24),

            // OR Separator
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text('OR',
                      style: textTheme.bodySmall
                          ?.copyWith(color: Colors.grey.shade600)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}