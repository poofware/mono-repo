// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/core/config/flavors.dart';
import 'package:poof_admin/core/providers/app_logger_provider.dart';
import 'package:poof_admin/core/providers/app_state_provider.dart';
import 'package:poof_admin/core/providers/auth_controller_provider.dart';
import 'package:poof_admin/features/auth/data/models/admin_login_request.dart';
import 'package:poof_admin/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_admin/features/auth/presentation/widgets/auth_page_wrapper.dart';
import 'package:poof_admin/features/auth/providers/admin_auth_providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_flutter_widgets/poof_flutter_widgets.dart';

class TotpVerifyPage extends ConsumerStatefulWidget {
  const TotpVerifyPage({super.key});

  @override
  ConsumerState<TotpVerifyPage> createState() => _TotpVerifyPageState();
}

class _TotpVerifyPageState extends ConsumerState<TotpVerifyPage> {
  String _code = '';
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    if (_code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit code')),
      );
      return;
    }

    if (_isLoading) return;
    setState(() => _isLoading = true);

    final logger = ref.read(appLoggerProvider);
    final authController = ref.read(authControllerProvider);
    final config = PoofAdminFlavorConfig.instance;
    final authState = ref.read(adminAuthStateNotifierProvider);

    if (authState.username.isEmpty || authState.password.isEmpty) {
      logger.e('TOTP Verify: Missing username/password from state. Redirecting.');
      context.go('/');
      return;
    }

    try {
      final creds = AdminLoginRequest(
        username: authState.username,
        password: authState.password,
        totpCode: _code,
      );

      if (!config.testMode) {
        await authController.signIn(creds);
      } else {
        logger.d('[TEST MODE] Skipping real login, manually setting state.');
        await Future.delayed(const Duration(seconds: 1));
        ref.read(appStateProvider.notifier).setLoggedIn(true);
      }
      if (mounted) context.go('/dashboard');
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: ${e.message}')),
      );
    } catch (e, st) {
      logger.e('TotpVerifyPage: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An unexpected error occurred: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        ref.read(adminAuthStateNotifierProvider.notifier).clearCredentials();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AuthPageWrapper(
      showBackButton: true,
      child: AuthFormCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter your code', style: textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text(
              'Enter the 6-digit code from your authenticator app.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            SixDigitField(
              autofocus: true,
              onChanged: (val) {
                setState(() => _code = val);
                if (val.length == 6) _handleLogin();
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: _isLoading
                  ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white))
                  : const Text('Sign In', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}