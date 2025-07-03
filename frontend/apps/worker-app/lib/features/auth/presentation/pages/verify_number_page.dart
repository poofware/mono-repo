// worker-app/lib/features/auth/presentation/pages/verify_number_page.dart

import 'dart:async'; // Import for Timer

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations

import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_flutter_widgets/poof_flutter_widgets.dart' show SixDigitField;

/// The arguments for this page are now simpler, only requiring the phone number.
class VerifyNumberArgs {
  final String phoneNumber;

  /// The optional `onSuccess` callback is now passed here.
  final Future<void> Function()? onSuccess;

  const VerifyNumberArgs({
    required this.phoneNumber,
    this.onSuccess,
  });
}

class VerifyNumberPage extends ConsumerStatefulWidget {
  final VerifyNumberArgs args;

  const VerifyNumberPage({super.key, required this.args});

  @override
  ConsumerState<VerifyNumberPage> createState() => _VerifyNumberPageState();
}

class _VerifyNumberPageState extends ConsumerState<VerifyNumberPage> {
  String _sixDigitCode = '';
  bool _isLoading = false;
  bool _isResending = false;

  // --- MODIFIED START: Cooldown timer state ---
  Timer? _resendTimer;
  int _secondsRemaining = 30;
  // A computed property is cleaner than managing another boolean flag.
  bool get _isResendButtonActive => _secondsRemaining == 0;
  // --- MODIFIED END ---

  @override
  void initState() {
    super.initState();
    // --- MODIFIED START: Start the initial countdown ---
    _startResendTimer();
    // --- MODIFIED END ---
  }

  @override
  void dispose() {
    // --- MODIFIED START: Always cancel the timer to prevent memory leaks ---
    _resendTimer?.cancel();
    // --- MODIFIED END ---
    super.dispose();
  }

  // --- MODIFIED START: Timer logic ---
  void _startResendTimer() {
    _resendTimer?.cancel(); // Cancel any existing timer
    _secondsRemaining = 30; // Reset to 30 seconds

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
        if (mounted) setState(() {}); // Final update to enable the button
      }
    });
  }
  // --- MODIFIED END ---

  Future<void> _onVerify() async {
    final appLocalizations = AppLocalizations.of(context);
    if (_sixDigitCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appLocalizations.verifyNumberEnter6DigitCode)),
      );
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final BuildContext capturedContext = context;

    final config = PoofWorkerFlavorConfig.instance;
    final phone = widget.args.phoneNumber;
    setState(() => _isLoading = true);

    final workerAuthRepo = ref.read(workerAuthRepositoryProvider);
    try {
      if (!config.testMode) {
        await workerAuthRepo.verifySMSCode(phone, _sixDigitCode);
      }
      if (widget.args.onSuccess != null) {
        await widget.args.onSuccess!();
      } else {
        if (navigator.canPop()) {
          navigator.pop(true);
        }
      }
    } on ApiException catch (e) {
      if (!capturedContext.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(userFacingMessage(capturedContext, e))),
      );
    } catch (e) {
      if (!capturedContext.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(capturedContext)
                .loginUnexpectedError(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onResendCode() async {
    // Use the computed property and local resending flag to guard.
    if (!_isResendButtonActive || _isResending) return;
    setState(() => _isResending = true);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final BuildContext capturedContext = context;
    final config = PoofWorkerFlavorConfig.instance;
    final phone = widget.args.phoneNumber;

    if (config.testMode) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(capturedContext)
                .verifyNumberTestModeNoResend)),
      );
      if (mounted) setState(() => _isResending = false);
      // In test mode, we can restart the timer for UI testing.
      _startResendTimer();
      return;
    }

    final workerAuthRepo = ref.read(workerAuthRepositoryProvider);
    try {
      await workerAuthRepo.requestSMSCode(phone);
      if (!capturedContext.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(capturedContext).verifyNumberCodeResent)),
      );
      // --- MODIFIED START: Restart the timer on success ---
      _startResendTimer();
      // --- MODIFIED END ---
    } on ApiException catch (e) {
      if (!capturedContext.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(userFacingMessage(capturedContext, e))),
      );
    } catch (e) {
      if (!capturedContext.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(capturedContext)
                .loginUnexpectedError(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.args.phoneNumber;
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: AppConstants.kDefaultPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(false),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      // Icon
                      const Icon(
                        Icons.sms_outlined,
                        size: 80,
                        color: AppColors.poofColor,
                      ).animate().fadeIn(delay: 200.ms, duration: 400.ms).scale(),
                      const SizedBox(height: 24),
                      // Title
                      Text(
                        appLocalizations.verifyNumberTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      )
                          .animate()
                          .fadeIn(delay: 300.ms, duration: 400.ms)
                          .slideY(begin: 0.2),
                      const SizedBox(height: 16),
                      // Message
                      Text(
                        appLocalizations.verifyNumberMessage(phone),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 16,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 400.ms, duration: 400.ms)
                          .slideY(begin: 0.2),
                      const SizedBox(height: 32),
                      // Input card
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 32),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            SixDigitField(
                              autofocus: true,
                              onChanged: (val) =>
                                  setState(() => _sixDigitCode = val),
                                  onSubmitted: (_) => _onVerify(),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  appLocalizations.verifyNumberDidNotReceiveCode,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                TextButton(
                                  onPressed: _isResendButtonActive
                                      ? _onResendCode
                                      : null,
                                  child: _isResending
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.blue.shade300,
                                          ),
                                        )
                                      : Text(
                                          _isResendButtonActive
                                              ? appLocalizations
                                                  .verifyNumberResendCode
                                              : appLocalizations
                                                  .verifyNumberResendCodeCooldown(
                                                      _secondsRemaining),
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: _isResendButtonActive
                                                ? Colors.blue
                                                : Colors.grey,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 500.ms, duration: 400.ms)
                          .slideY(begin: 0.2),
                    ],
                  ),
                ),
              ),
              WelcomeButton(
                text: appLocalizations.verifyNumberVerifyButton,
                isLoading: _isLoading,
                onPressed:
                    (_isLoading || _sixDigitCode.length != 6) ? null : _onVerify,
              ).animate().fadeIn(delay: 600.ms, duration: 400.ms).slideY(begin: 0.5),
            ],
          ),
        ),
      ),
    );
  }
}
