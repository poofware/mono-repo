// worker-app/lib/features/auth/presentation/pages/phone_verification_info_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';

import 'verify_number_page.dart' show VerifyNumberArgs;

/// Arguments passed to [PhoneVerificationInfoPage].
/// The optional [onSuccess] callback is executed after successful SMS verification.
/// If [onSuccess] is null, the page will simply pop with a `true` result.
class PhoneVerificationInfoArgs {
  final String phoneNumber;
  final Future<void> Function()? onSuccess;
  // If true, this flow is part of sign-up and should lead to TOTP setup.
  // Defaults to false for MyProfile and other flows.
  final bool goToTotpAfterSuccess;

  const PhoneVerificationInfoArgs({
    required this.phoneNumber,
    this.onSuccess,
    this.goToTotpAfterSuccess = false,
  });
}

/// A page that explains why we’re verifying the phone number,
/// sends the SMS code, and then orchestrates the verification flow.
class PhoneVerificationInfoPage extends ConsumerStatefulWidget {
  final PhoneVerificationInfoArgs args;

  const PhoneVerificationInfoPage({super.key, required this.args});

  @override
  ConsumerState<PhoneVerificationInfoPage> createState() =>
      _PhoneVerificationInfoPageState();
}

class _PhoneVerificationInfoPageState
    extends ConsumerState<PhoneVerificationInfoPage> {
  bool _isLoading = false;

  /// Handles the entire verification flow:
  /// 1. Requests the SMS code from the server.
  /// 2. Pushes the VerifyNumberPage and waits for a result.
  /// 3. If verification is successful, it executes the optional [onSuccess]
  ///    callback or pops the navigator with a `true` result.
  Future<void> _onSendCodeAndVerify() async {
    // Capture context before async gaps
    final router = GoRouter.of(context);
    final BuildContext capturedContext = context;

    final config = PoofWorkerFlavorConfig.instance;
    final phone = widget.args.phoneNumber;

    setState(() => _isLoading = true);

    try {
      // Step 1: Request the SMS code from the server (unless in test mode)
      if (!config.testMode) {
        final authRepo = ref.read(workerAuthRepositoryProvider);
        await authRepo.requestSMSCode(phone);
      }

      // Step 2: Navigate to VerifyNumberPage.
      // - Sign-up flow (goToTotpAfterSuccess=true): replace to avoid flicker and
      //   to ensure back-swipe shows CreateAccount.
      // - MyProfile or other flows: push and await result so caller receives a
      //   boolean and can proceed (no TOTP navigation).
      if (widget.args.goToTotpAfterSuccess) {
        if (mounted) setState(() => _isLoading = false);
        router.replaceNamed(
          AppRouteNames.verifyNumberPage,
          extra: VerifyNumberArgs(
            phoneNumber: phone,
            onSuccess: widget.args.onSuccess,
            goToTotpAfterSuccess: true,
          ),
        );
        return;
      }

      final result = await router.pushNamed<bool>(
        AppRouteNames.verifyNumberPage,
        extra: VerifyNumberArgs(
          phoneNumber: phone,
          onSuccess: widget.args.onSuccess,
          goToTotpAfterSuccess: false,
        ),
      );

      // If verification not successful, stop here.
      if (result != true) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Success for non-signup flows: optional callback then pop(true) so
      // the caller (e.g., MyProfile) can proceed and clear loading.
      if (widget.args.onSuccess != null) {
        await widget.args.onSuccess!();
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop(true);
      }
      return;
    } on ApiException catch (e) {
      if (!capturedContext.mounted) return;
      showAppSnackBar(
        capturedContext,
        Text(userFacingMessage(capturedContext, e)),
      );
    } catch (e) {
      if (!capturedContext.mounted) return;
      showAppSnackBar(
        capturedContext,
        Text(
          AppLocalizations.of(
            capturedContext,
          ).loginUnexpectedError(e.toString()),
        ),
      );
    } finally {
      // The loading state will naturally resolve when this page is popped
      // or navigated away from by the onSuccess callback. If it's still mounted,
      // we ensure the spinner stops.
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.args.phoneNumber;
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 80,
                  color: AppColors.poofColor,
                ).animate().fadeIn(delay: 200.ms, duration: 400.ms).scale(),

                const SizedBox(height: 24),

                Text(
                  appLocalizations.phoneVerificationInfoTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 300.ms, duration: 400.ms)
                    .slideY(begin: 0.2),

                const SizedBox(height: 12),

                Text(
                  appLocalizations.phoneVerificationInfoMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                )
                    .animate()
                    .fadeIn(delay: 400.ms, duration: 400.ms)
                    .slideY(begin: 0.2),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    phone.isEmpty
                        ? appLocalizations.phoneVerificationInfoNoNumber
                        : phone,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(delay: 500.ms, duration: 400.ms)
                    .slideY(begin: 0.2),

                const SizedBox(height: 24),

                WelcomeButton(
                  text: appLocalizations.phoneVerificationInfoSendCodeButton,
                  isLoading: _isLoading,
                  onPressed: _isLoading ? null : _onSendCodeAndVerify,
                )
                    .animate()
                    .fadeIn(delay: 600.ms, duration: 400.ms)
                    .slideY(begin: 0.2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
