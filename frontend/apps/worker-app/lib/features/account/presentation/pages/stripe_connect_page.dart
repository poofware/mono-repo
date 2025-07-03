// lib/features/account/presentation/pages/stripe_connect_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/features/account/providers/providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

import '../../utils/stripe_utils.dart';
import 'package:poof_worker/core/presentation/utils/url_launcher_utils.dart'; // Import URL launcher

class StripePage extends ConsumerStatefulWidget {
  const StripePage({super.key});

  @override
  ConsumerState<StripePage> createState() => _StripePageState();
}

class _StripePageState extends ConsumerState<StripePage> {
  bool _isLoading = false;

  Future<void> _onConnectWithStripe() async {
    final config = PoofWorkerFlavorConfig.instance;
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final BuildContext capturedContext = context;

    if (config.testMode) {
      router.pushNamed('StripeConnectInProgressPage');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(workerAccountRepositoryProvider);
      final success = await startStripeConnectFlow(router: router, repo: repo);
      if (!success) {
        if (!capturedContext.mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(capturedContext).urlLauncherCannotLaunch)),
        );
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
            content: Text(
                AppLocalizations.of(capturedContext).loginUnexpectedError(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: AppConstants.kDefaultPadding,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Center(
                          child: Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 64,
                            color: AppColors.poofColor,
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 200.ms, duration: 400.ms)
                            .scale(
                              begin: const Offset(0.8, 0.8),
                              end: const Offset(1, 1),
                              curve: Curves.easeOutBack,
                            ),
                        const SizedBox(height: 24),
                        Text(
                          appLocalizations.stripeConnectPageTitle,
                          style: theme.textTheme.headlineLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        )
                            .animate()
                            .fadeIn(delay: 300.ms)
                            .slideX(
                                begin: -0.1,
                                duration: 400.ms,
                                curve: Curves.easeOutCubic),
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            appLocalizations.stripeConnectPageSubtitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 400.ms)
                            .slideX(
                                begin: -0.1,
                                duration: 400.ms,
                                curve: Curves.easeOutCubic),
                        Padding(
                          padding: const EdgeInsets.only(
                              top: AppConstants.kLargeVerticalSpacing),
                          child: Container(
                            padding: AppConstants.kDefaultPadding,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appLocalizations.stripeConnectPageHowItWorksTitle,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: AppConstants.kDefaultVerticalSpacing),
                                  child: _buildStep(
                                    number: '1',
                                    title:
                                        appLocalizations.stripeConnectPageStep1Title,
                                    subtitle: appLocalizations
                                        .stripeConnectPageStep1Subtitle,
                                    circleColor:
                                        const Color.fromARGB(90, 65, 179, 214),
                                    numberColor:
                                        const Color.fromARGB(255, 65, 179, 214),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: AppConstants.kDefaultVerticalSpacing),
                                  child: _buildStep(
                                    number: '2',
                                    title:
                                        appLocalizations.stripeConnectPageStep2Title,
                                    subtitle: appLocalizations
                                        .stripeConnectPageStep2Subtitle,
                                    circleColor:
                                        const Color.fromARGB(90, 95, 184, 99),
                                    numberColor:
                                        const Color.fromARGB(255, 95, 184, 99),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: AppConstants.kDefaultVerticalSpacing),
                                  child: _buildStep(
                                    number: '3',
                                    title:
                                        appLocalizations.stripeConnectPageStep3Title,
                                    subtitle: appLocalizations
                                        .stripeConnectPageStep3Subtitle,
                                    circleColor:
                                        const Color.fromARGB(90, 239, 91, 12),
                                    numberColor:
                                        const Color.fromARGB(255, 239, 91, 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(appLocalizations
                                          .stripeConnectPageTermsSnackbar)),
                                );
                              },
                              child: Text(
                                appLocalizations.stripeConnectPageTermsButton,
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.blue),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(appLocalizations
                                          .stripeConnectPagePrivacySnackbar)),
                                );
                              },
                              child: Text(
                                appLocalizations.stripeConnectPagePrivacyButton,
                                style: const TextStyle(
                                    fontSize: 14, color: Colors.blue),
                              ),
                            ),
                          ],
                        ).animate().fadeIn(delay: 600.ms),
                      ],
                    ),
                  ),
                ),
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          appLocalizations.stripeConnectPageNeedHelpLabel,
                          style: const TextStyle(fontSize: 14),
                        ),
                        _StatefulSupportButton(
                          text:
                              appLocalizations.stripeConnectPageContactSupportButton,
                          onPressed: () => tryLaunchUrl('mailto:team@thepoofapp.com'),
                        ),
                      ],
                    ),
                    WelcomeButton(
                      text: appLocalizations.stripeConnectPageConnectButton,
                      isLoading: _isLoading,
                      onPressed: _isLoading ? null : _onConnectWithStripe,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required String number,
    required String title,
    required String subtitle,
    required Color circleColor,
    required Color numberColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: circleColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: numberColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A stateful button for the support link to show a loading state.
class _StatefulSupportButton extends StatefulWidget {
  final String text;
  final Future<void> Function() onPressed;

  const _StatefulSupportButton({required this.text, required this.onPressed});

  @override
  State<_StatefulSupportButton> createState() => _StatefulSupportButtonState();
}

class _StatefulSupportButtonState extends State<_StatefulSupportButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _isLoading
          ? null
          : () async {
              setState(() => _isLoading = true);
              try {
                await widget.onPressed();
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
      child: _isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              widget.text,
              style: const TextStyle(fontSize: 14, color: Colors.blue),
            ),
    );
  }
}

