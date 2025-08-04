// worker-app/lib/features/auth/presentation/pages/totp_verify_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_flutter_widgets/poof_flutter_widgets.dart'
    show SixDigitField;
import 'package:poof_worker/l10n/generated/app_localizations.dart';

/// Arguments for the unified TOTP verification page.
class TotpVerifyArgs {
  /// The email or phone number to display to the user.
  final String displayIdentifier;

  /// The callback to execute with the entered code upon successful submission.
  /// This encapsulates the specific logic (login vs. register).
  final Future<void> Function(String totpCode) onSuccess;

  const TotpVerifyArgs({
    required this.displayIdentifier,
    required this.onSuccess,
  });
}

class TotpVerifyPage extends ConsumerStatefulWidget {
  final TotpVerifyArgs args;
  const TotpVerifyPage({super.key, required this.args});

  @override
  ConsumerState<TotpVerifyPage> createState() => _TotpVerifyPageState();
}

class _TotpVerifyPageState extends ConsumerState<TotpVerifyPage> {
  String _sixDigitCode = '';
  bool _isLoading = false;

  Future<void> _handleVerification() async {
    setState(() => _isLoading = true);

    try {
      await widget.args.onSuccess(_sixDigitCode);
      // Allow any navigation triggered by the success callback to take effect
      // before potentially resetting the loading state.
      await Future<void>.delayed(Duration.zero);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: AppConstants.kDefaultPadding,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => context.pop(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Icon(
                              Icons.phonelink_lock_outlined,
                              size: 80,
                              color: AppColors.poofColor,
                            )
                            .animate()
                            .fadeIn(delay: 200.ms, duration: 400.ms)
                            .scale(),
                        const SizedBox(height: 24),
                        Text(
                              appLocalizations.totpVerifyTitle,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            )
                            .animate()
                            .fadeIn(delay: 300.ms, duration: 400.ms)
                            .slideY(begin: 0.2),
                        const SizedBox(height: 16),
                        Text(
                              appLocalizations.totpVerifyExplanation,
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
                        Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 32,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  SixDigitField(
                                    autofocus: true,
                                    showPasteButton: true,
                                    onChanged: (val) =>
                                        setState(() => _sixDigitCode = val),
                                    onSubmitted: (code) =>
                                        _handleVerification(),
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
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child:
                      WelcomeButton(
                            text: appLocalizations.totpVerifyButton,
                            isLoading: _isLoading,
                            onPressed: (_isLoading || _sixDigitCode.length != 6)
                                ? null
                                : _handleVerification,
                          )
                          .animate()
                          .fadeIn(delay: 600.ms, duration: 400.ms)
                          .slideY(begin: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
