import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_flutter_widgets/poof_flutter_widgets.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/core/providers/app_logger_provider.dart';
import 'package:poof_pm/core/providers/app_state_provider.dart';
import 'package:poof_pm/core/providers/auth_controller_provider.dart';
import 'package:poof_pm/features/auth/data/models/pm_login_request.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_page_wrapper.dart';

/// The second step of the login flow, where the user enters their 6-digit
/// TOTP code after providing their email on the WelcomePage.
class LoginVerifyCodePage extends ConsumerStatefulWidget {
  final String email;
  const LoginVerifyCodePage({super.key, required this.email});

  @override
  ConsumerState<LoginVerifyCodePage> createState() =>
      _LoginVerifyCodePageState();
}

class _LoginVerifyCodePageState extends ConsumerState<LoginVerifyCodePage> {
  String _code = '';
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    if (_code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit code')),
      );
      return;
    }

    // Prevent multiple submissions while one is in progress
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final logger = ref.read(appLoggerProvider);
    final authController = ref.read(authControllerProvider);
    final config = PoofPMFlavorConfig.instance;

    try {
      final creds = PmLoginRequest(email: widget.email, totpCode: _code);
      if (!config.testMode) {
        await authController.signIn(creds);
      } else {
        // Test mode => skip real call, manually set login state
        logger.d('[TEST MODE] Skipping real login, manually setting state.');
        await Future.delayed(const Duration(seconds: 1));
        ref.read(appStateProvider.notifier).setLoggedIn(true);
      }

      if (!mounted) return;
      // GoRouter redirect logic handles navigation on success
      context.go('/main');
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: ${e.message}')),
      );
    } catch (e, st) {
      logger.e('LoginVerifyCodePage: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An unexpected error occurred: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return AuthPageWrapper(
      showBackButton: true,
      // MODIFICATION: Replaced boilerplate Container with AuthFormCard.
      child: AuthFormCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your code',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Enter the 6-digit code from your authenticator app for ${widget.email}.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            SixDigitField(
              autofocus: true,
              onChanged: (val) {
                setState(() => _code = val);
                // Trigger login automatically when 6 digits are entered.
                if (val.length == 6) {
                  _handleLogin();
                }
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.white))
                  : const Text('Sign In',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () {
                  // Simple navigation back to the welcome page
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/');
                  }
                },
                child: Text(
                  "Use a different email",
                  style: TextStyle(color: colorScheme.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}