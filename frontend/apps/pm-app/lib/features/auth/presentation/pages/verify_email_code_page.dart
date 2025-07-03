import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poof_pm/core/theme/app_constants.dart';
import 'package:poof_pm/core/theme/app_colors.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/features/auth/providers/pm_auth_providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_pm/core/providers/app_logger_provider.dart';
import 'package:poof_flutter_widgets/poof_flutter_widgets.dart' show SixDigitField;

/// User enters the 6-digit email code. On success, we proceed to TOTP setup.
class VerifyEmailCodePage extends ConsumerStatefulWidget {
  const VerifyEmailCodePage({super.key});

  @override
  ConsumerState<VerifyEmailCodePage> createState()
      => _VerifyEmailCodePageState();
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
        const SnackBar(content: Text('No email found in sign-up state. Cannot resend.')),
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
                'Enter Email Code',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              const Text(
                'We sent a 6-digit code to your email. '
                'Please enter it below to verify your email address.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: AppConstants.kLargeVerticalSpacing),

              SixDigitField(
                autofocus: true,
                onChanged: (val) => setState(() => _code = val),
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Didn't receive a code? "),
                  TextButton(
                    onPressed: _onResend,
                    child: const Text(
                      'Resend',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              const Spacer(),

              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _onVerify,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: const Text('Verify Code'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

