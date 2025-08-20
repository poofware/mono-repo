import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/core/providers/app_logger_provider.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_page_wrapper.dart';
import 'package:poof_pm/features/auth/providers/pm_auth_providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_flutter_widgets/poof_flutter_widgets.dart' show SixDigitField;

/// User enters the 6-digit email code. On success, we proceed to TOTP setup.
class VerifyEmailCodePage extends ConsumerStatefulWidget {
  const VerifyEmailCodePage({super.key});

  @override
  ConsumerState<VerifyEmailCodePage> createState() =>
      _VerifyEmailCodePageState();
}

class _VerifyEmailCodePageState extends ConsumerState<VerifyEmailCodePage> {
  String _code = '';
  bool _isLoading = false;

  Future<void> _onVerify() async {
    if (_code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit code')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final config = PoofPMFlavorConfig.instance;
    final pmAuthRepo = ref.read(pmAuthRepositoryProvider);
    final logger = ref.read(appLoggerProvider);
    final email = ref.read(pmSignUpStateNotifierProvider).email;

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email found in sign-up state.')),
      );
      setState(() => _isLoading = false);
      return;
    }

    try {
      // If not test mode => verify with real call
      if (!config.testMode) {
        await pmAuthRepo.verifyEmailCode(email, _code);
      } else {
        logger.d('[TEST MODE] Skipping real verifyEmailCode');
        await Future.delayed(const Duration(milliseconds: 700));
      }

      if (!mounted) return;
      // Next step -> TOTP setup
      context.push('/totp_setup');
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification failed: ${e.message}')),
      );
    } catch (e, st) {
      logger.e('VerifyEmailCodePage: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onResend() async {
    final config = PoofPMFlavorConfig.instance;
    final pmAuthRepo = ref.read(pmAuthRepositoryProvider);
    final logger = ref.read(appLoggerProvider);
    final email = ref.read(pmSignUpStateNotifierProvider).email;

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No email found in sign-up state. Cannot resend.')),
      );
      return;
    }

    try {
      if (!config.testMode) {
        await pmAuthRepo.requestEmailCode(email);
      } else {
        logger.d('[TEST MODE] Skipping real requestEmailCode (resend).');
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification code resent!')),
      );
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resend: ${e.message}')),
      );
    } catch (e) {
      logger.e('VerifyEmailCodePage: resend error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
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
            const SizedBox(height: 24),
            Text(
              'Enter the 6-digit code we sent to your email address.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            SixDigitField(
              autofocus: true,
              onChanged: (val) => setState(() => _code = val),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : _onVerify,
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
                  : const Text('Verify Code',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: _onResend,
                child: Text(
                  "Didn't receive a code? Resend",
                  style: TextStyle(
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}