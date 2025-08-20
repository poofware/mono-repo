// lib/features/account/presentation/pages/stripe_idv_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/features/account/providers/providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/presentation/utils/url_launcher_utils.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';

import '../../utils/stripe_utils.dart';

class VerifyIdentityPage extends ConsumerStatefulWidget {
  const VerifyIdentityPage({super.key});

  @override
  ConsumerState<VerifyIdentityPage> createState() => _VerifyIdentityPageState();
}

class _VerifyIdentityPageState extends ConsumerState<VerifyIdentityPage> {
  bool _isLoading = false;

  Future<void> _onStartIdVerification() async {
    final config = PoofWorkerFlavorConfig.instance;
    if (!mounted) return;
    final router = GoRouter.of(context);
    final BuildContext capturedContext = context;

    if (config.testMode) {
      router.pushNamed(AppRouteNames.stripeIdvInProgressPage);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final workerAccountRepo = ref.read(workerAccountRepositoryProvider);
      final success = await startStripeIdentityFlow(
        router: router,
        repo: workerAccountRepo,
      );
      if (!success) {
        if (!capturedContext.mounted) return;
        showAppSnackBar(
          capturedContext,
          Text(AppLocalizations.of(capturedContext).urlLauncherCannotLaunch),
        );
      }
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Center(
                              child: Icon(
                                Icons.badge_outlined,
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
                              appLocalizations.stripeIdvPageTitle,
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            )
                            .animate()
                            .fadeIn(delay: 300.ms)
                            .slideX(
                              begin: -0.1,
                              duration: 400.ms,
                              curve: Curves.easeOutCubic,
                            ),
                        Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                appLocalizations.stripeIdvPageExplanation,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                            .animate()
                            .fadeIn(delay: 400.ms)
                            .slideX(
                              begin: -0.1,
                              duration: 400.ms,
                              curve: Curves.easeOutCubic,
                            ),
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                _buildStepRow(
                                  icon: FontAwesomeIcons.fileLines,
                                  text:
                                      appLocalizations.stripeIdvPageStepScanId,
                                ),
                                _buildStepRow(
                                  icon: FontAwesomeIcons.user,
                                  text:
                                      appLocalizations.stripeIdvPageStepSelfie,
                                ),
                                _buildStepRow(
                                  icon: FontAwesomeIcons.check,
                                  text:
                                      appLocalizations.stripeIdvPageStepSubmit,
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2),
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Text(
                            appLocalizations.stripeIdvPageBeforeYouBeginTitle,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 20,
                            ),
                          ),
                        ).animate().fadeIn(delay: 600.ms),
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                _buildStepRow(
                                  icon: FontAwesomeIcons.exclamation,
                                  text:
                                      appLocalizations.stripeIdvPageTipDuration,
                                ),
                                _buildStepRow(
                                  icon: FontAwesomeIcons.lightbulb,
                                  text:
                                      appLocalizations.stripeIdvPageTipLighting,
                                ),
                                _buildStepRow(
                                  icon: FontAwesomeIcons.idCard,
                                  text: appLocalizations.stripeIdvPageTipHaveId,
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.2),
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Text(
                            appLocalizations.stripeIdvPageSecurityNote,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ).animate().fadeIn(delay: 800.ms),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            appLocalizations.stripeIdvPageNeedHelpLabel,
                            style: const TextStyle(fontSize: 14),
                          ),
                          _StatefulSupportButton(
                            text: appLocalizations
                                .stripeIdvPageContactSupportButton,
                            onPressed: () =>
                                tryLaunchUrl('mailto:team@thepoofapp.com'),
                          ),
                        ],
                      ),
                      WelcomeButton(
                        text: appLocalizations.stripeIdvPageStartButton,
                        isLoading: _isLoading,
                        onPressed: _isLoading ? null : _onStartIdVerification,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.poofColor),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(text, style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
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
