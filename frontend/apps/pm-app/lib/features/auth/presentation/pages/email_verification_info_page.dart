import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/core/providers/app_logger_provider.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_pm/features/auth/presentation/widgets/auth_page_wrapper.dart';
import 'package:poof_pm/features/auth/providers/pm_auth_providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;

/// Explains that we will send a one-time code to the user's email
/// (they already provided it earlier). Provides a button to
/// "Send Verification Code," and navigates to /verify_email_code.
class EmailVerificationInfoPage extends ConsumerStatefulWidget {
  const EmailVerificationInfoPage({super.key});

  @override
  ConsumerState<EmailVerificationInfoPage> createState() =>
      _EmailVerificationInfoPageState();
}

class _EmailVerificationInfoPageState
    extends ConsumerState<EmailVerificationInfoPage> {
  bool _isSending = false;

  Future<void> _onSendCode() async {
    setState(() => _isSending = true);
    final logger = ref.read(appLoggerProvider);
    final config = PoofPMFlavorConfig.instance;
    final pmAuthRepo = ref.read(pmAuthRepositoryProvider);

    // We read the email from the pmSignUpState
    final pmSignUpState = ref.read(pmSignUpStateNotifierProvider);

    if (pmSignUpState.email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No email to verify! Go back and fill your info.')),
      );
      setState(() => _isSending = false);
      return;
    }

    try {
      // If not in test mode, request the email code for real
      if (!config.testMode) {
        await pmAuthRepo.requestEmailCode(pmSignUpState.email);
      } else {
        logger.d('[TEST MODE] Skipping real requestEmailCode');
        await Future.delayed(const Duration(milliseconds: 700));
      }

      if (!mounted) return;
      // Then go to /verify_email_code
      context.push('/verify_email_code');
    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to request email code: ${e.message}')),
      );
    } catch (e, st) {
      logger.e('EmailVerificationInfoPage: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unexpected error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final pmSignUpState = ref.watch(pmSignUpStateNotifierProvider);
    final email = pmSignUpState.email.isEmpty
        ? 'someone@example.com'
        : pmSignUpState.email;

    return AuthPageWrapper(
      showBackButton: true,
      // MODIFICATION: Replaced boilerplate Container with AuthFormCard.
      child: AuthFormCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verify Your Email',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Step 3 of 4: Email Verification',
              style: textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Text(
              'To secure your account, we need to verify your email address. We will send a one-time verification code to:',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                email,
                style:
                    textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSending ? null : _onSendCode,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSending
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.white))
                  : const Text('Send Verification Code',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}