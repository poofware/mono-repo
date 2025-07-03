import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poof_pm/core/theme/app_constants.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/features/auth/providers/pm_auth_providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_pm/core/providers/app_logger_provider.dart';

/// Explains that we will send a one-time code to the user's email
/// (they already provided it earlier). Provides a button to 
/// "Send Verification Code," and navigates to /verify_email_code.
class EmailVerificationInfoPage extends ConsumerStatefulWidget {
  const EmailVerificationInfoPage({super.key});

  @override
  ConsumerState<EmailVerificationInfoPage> createState()
      => _EmailVerificationInfoPageState();
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
        const SnackBar(content: Text('No email to verify! Go back and fill your info.')),
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
    final pmSignUpState = ref.watch(pmSignUpStateNotifierProvider);
    final email = pmSignUpState.email.isEmpty
        ? 'someone@example.com'
        : pmSignUpState.email;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: AppConstants.kDefaultPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),

              const SizedBox(height: AppConstants.kLargeVerticalSpacing),
              const Text(
                'Verify Your Email',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              Text(
                'We’ll send a code to:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                email,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppConstants.kLargeVerticalSpacing),

              const Text(
                'Email verification ensures only you can access this account. '
                'Tap below to send a verification code to your inbox.',
                style: TextStyle(fontSize: 16),
              ),
              const Spacer(),

              _isSending
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _onSendCode,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: const Text('Send Verification Code'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

