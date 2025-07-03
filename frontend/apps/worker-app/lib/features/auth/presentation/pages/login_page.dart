// worker-app/lib/features/auth/presentation/pages/login_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/providers/app_providers.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

import '../widgets/phone_number_field.dart';
import 'totp_verify_page.dart';
import '../../data/models/login_worker_request.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/utils/error_utils.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  String _combinedPhone = '';
  // Add a loading state to prevent multiple taps during navigation.
  bool _isLoading = false;
  bool _isPhoneValid = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _onVerifyAndLogin(String totpCode) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final logger = ref.read(appLoggerProvider);
    final config = PoofWorkerFlavorConfig.instance;

    try {
      if (config.testMode) {
        logger.d('Test mode: skipping real TOTP login, setting state.');
        ref.read(appStateProvider.notifier).setLoggedIn(true);
        router.goNamed(AppRouteNames.mainTab);
        return;
      }

      final creds = LoginWorkerRequest(phoneNumber: _combinedPhone, totpCode: totpCode);
      await ref.read(authControllerProvider).signIn(creds, router);
    } on ApiException catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(userFacingMessage(context, e))),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).loginUnexpectedError(e.toString())),
          ),
        );
      }
    }
  }

  Future<void> _handleContinue() async {
    if (_isLoading) return; // Guard against multiple taps

    setState(() => _isLoading = true);

    // This logic now just navigates to the unified verify page
    await context.pushNamed(
      AppRouteNames.totpVerifyPage,
      extra: TotpVerifyArgs(
        displayIdentifier: _combinedPhone,
        onSuccess: _onVerifyAndLogin,
      ),
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
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
                      // Back button to return to the welcome page
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.goNamed(AppRouteNames.home);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      // Icon
                      const Center(
                        child: Icon(
                          Icons.login,
                          size: 64,
                          color: AppColors.poofColor,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 400.ms)
                          .scale(
                              begin: const Offset(0.8, 0.8),
                              end: const Offset(1, 1),
                              curve: Curves.easeOutBack),
                      const SizedBox(height: 24),
                      // Title
                      Text(
                        appLocalizations.loginTitle,
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 300.ms)
                          .slideX(
                              begin: -0.1,
                              duration: 400.ms,
                              curve: Curves.easeOutCubic),
                      // Subtitle
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          appLocalizations.loginSubtitle,
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
                      const SizedBox(height: 32),
                      PhoneNumberField(
                        autofocus: false,
                        labelText:
                            appLocalizations.phoneNumberFieldLabel, // Localized label
                        onChanged: (fullNumber, isValid) {
                          _combinedPhone = fullNumber;
                          if (isValid != _isPhoneValid) {
                            setState(() {
                              _isPhoneValid = isValid;
                            });
                          }
                        },
                        initialDialCode: '+1', // or your default
                      ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
                    ],
                  ),
                ),
              ),
              // Button pinned to the bottom
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: WelcomeButton(
                  text: appLocalizations.loginContinueButton,
                  isLoading: _isLoading,
                  onPressed: _isPhoneValid ? _handleContinue : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
