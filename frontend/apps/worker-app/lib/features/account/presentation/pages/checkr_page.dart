import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';

import '../../data/models/worker.dart';
import '../../providers/providers.dart';

class BackgroundCheckPage extends ConsumerStatefulWidget {
  const BackgroundCheckPage({super.key});

  @override
  ConsumerState<BackgroundCheckPage> createState() =>
      _BackgroundCheckPageState();
}

class _BackgroundCheckPageState extends ConsumerState<BackgroundCheckPage> {
  bool _isLoading = false;
  bool _hasInitFields = false;
  final TextEditingController _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _startCheckrFlow() async {
    if (_isLoading) return;

    final router = GoRouter.of(context);
    final BuildContext capturedContext = context;
    final config = PoofWorkerFlavorConfig.instance;

    if (config.testMode) {
      router.pushNamed(AppRouteNames.checkrInProgressPage, extra: 'TEST-URL');
      return;
    }

    setState(() => _isLoading = true);
    final repo = ref.read(workerAccountRepositoryProvider);

    try {
      final newEmail = _emailController.text.trim();
      final worker = ref.read(workerStateNotifierProvider).worker;

      if (worker != null && worker.email != newEmail) {
        await repo.patchWorker(WorkerPatchRequest(email: newEmail));
      }

      final invite = await repo.createCheckrInvitation();
      await router.pushNamed(
        AppRouteNames.checkrInProgressPage,
        extra: invite.invitationUrl,
      );
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
    final config = PoofWorkerFlavorConfig.instance;
    final worker = ref.watch(workerStateNotifierProvider).worker;
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (!config.testMode && worker == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasInitFields && worker != null) {
      _emailController.text = worker.email;
      _hasInitFields = true;
    }

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
                                Icons.policy_outlined,
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
                              appLocalizations.checkrPageAuthTitle,
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
                              padding: const EdgeInsets.only(top: 16.0),
                              child: Text(
                                appLocalizations.checkrPageExplanation,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  height: 1.5,
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
                        const SizedBox(height: 32),
                        Text(
                          appLocalizations.checkrPageConfirmEmailLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
                        const SizedBox(height: 8),
                        Text(
                          appLocalizations.checkrPageConfirmEmailExplanation,
                          style: theme.textTheme.bodyMedium,
                        ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText:
                                appLocalizations.checkrPageEmailFieldLabel,
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.poofColor,
                                width: 2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.poofColor,
                                width: 2,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Column(
                    children: [
                      Center(
                        child: Text(
                          appLocalizations.checkrPageSecureWindowNote,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      WelcomeButton(
                        text: appLocalizations.checkrPageBeginButton,
                        isLoading: _isLoading,
                        onPressed: _isLoading ? null : _startCheckrFlow,
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
}
