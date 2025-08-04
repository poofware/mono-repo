// worker-app/lib/features/auth/presentation/pages/totp_signup_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/presentation/utils/url_launcher_utils.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';
import 'package:android_intent_plus/flag.dart';

import 'totp_verify_page.dart';
import '../../data/models/register_worker_request.dart';

class TotpSignUpPage extends ConsumerWidget {
  const TotpSignUpPage({super.key});

  // --- Asset Constants ---
  static const _kGoogleAuthIcon = 'assets/vectors/Google_Authenticator.svg';
  static const _kAuthyIcon = 'assets/vectors/authy-icon.svg';
  static const _kAppStoreBadge =
      'assets/vectors/Download_on_the_App_Store_Badge.svg';
  static const _kGooglePlayBadge =
      'assets/vectors/Google_Play_Store_badge_EN.svg';

  // --- Store URLs ---
  static const _googleAuthAndroidUrl =
      'https://play.google.com/store/apps/details?id=com.google.android.apps.authenticator2';
  static const _googleAuthIosUrl =
      'https://apps.apple.com/us/app/google-authenticator/id388497605';
  static const _authyAndroidUrl =
      'https://play.google.com/store/apps/details?id=com.authy.authy';
  static const _authyIosUrl = 'https://apps.apple.com/us/app/authy/id494168017';

  /// Copy the TOTP secret to clipboard for the user.
  void _copySecretToClipboard(BuildContext context, WidgetRef ref) {
    final secret = ref.read(signUpProvider).totpSecret;
    final appLocalizations = AppLocalizations.of(context);
    if (secret.isEmpty) {
      showAppSnackBar(context, Text(appLocalizations.totpSignupNoSecretFound));
      return;
    }
    Clipboard.setData(ClipboardData(text: secret));
    showAppSnackBar(context, Text(appLocalizations.totpSignupKeyCopied));
  }

  /// Tries to launch the otpauth:// deep link, falling back to the app store.
  Future<void> _openAuthenticator(
    BuildContext context,
    String otpAuthUri,
  ) async {
    final storeUrl = Platform.isAndroid
        ? _googleAuthAndroidUrl
        : _googleAuthIosUrl;

    if (Platform.isAndroid) {
      // Use android_intent_plus for better control over the task stack.
      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: otpAuthUri,
        category: 'android.intent.category.BROWSABLE',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK], // This is the key change
      );
      try {
        await intent.launch();
      } catch (e) {
        // If no app can handle the intent, open the Play Store.
        if (context.mounted) {
          await tryLaunchUrl(storeUrl);
        }
      }
    } else {
      // iOS handles this correctly with the default url_launcher.
      final bool didOpenApp = await tryLaunchUrl(otpAuthUri);
      if (!didOpenApp && context.mounted) {
        await tryLaunchUrl(storeUrl);
      }
    }
  }

  /// The registration logic to be executed on the verification page.
  Future<void> _onVerifyAndRegister(
    BuildContext context,
    WidgetRef ref,
    String totpCode,
  ) async {
    final router = GoRouter.of(context);
    final signUpState = ref.read(signUpProvider);
    final authRepo = ref.read(workerAuthRepositoryProvider);

    try {
      final config = PoofWorkerFlavorConfig.instance;
      if (!config.testMode) {
        final req = RegisterWorkerRequest(
          firstName: signUpState.firstName,
          lastName: signUpState.lastName,
          email: signUpState.email,
          phoneNumber: signUpState.phoneNumber,
          totpSecret: signUpState.totpSecret,
          totpToken: totpCode,
        );
        await authRepo.doRegister(req);
      }
      router.goNamed(AppRouteNames.signupSuccessPage);
    } on ApiException catch (e) {
      if (e.errorCode == 'phone_not_verified') {
        router.goNamed(AppRouteNames.signupExpiredPage);
      } else if (context.mounted) {
        showAppSnackBar(context, Text(userFacingMessage(context, e)));
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          Text(AppLocalizations.of(context).loginUnexpectedError(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final signUpState = ref.watch(signUpProvider);
    final otpAuthUri =
        'otpauth://totp/Poof%20Worker:${signUpState.phoneNumber}?secret=${signUpState.totpSecret}&issuer=Poof%20Worker';

    final String googleStoreBadgeAsset = Platform.isAndroid
        ? _kGooglePlayBadge
        : _kAppStoreBadge;
    final String googleStoreUrl = Platform.isAndroid
        ? _googleAuthAndroidUrl
        : _googleAuthIosUrl;
    final String authyStoreUrl = Platform.isAndroid
        ? _authyAndroidUrl
        : _authyIosUrl;

    return Scaffold(
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
                          onPressed: () =>
                              context.goNamed(AppRouteNames.createAccountPage),
                        ),
                      ),
                      const SizedBox(height: 16),
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
                            appLocalizations.totpSignupTitle,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 300.ms, duration: 400.ms)
                          .slideY(begin: 0.2),
                      const SizedBox(height: 8),
                      Text(
                            appLocalizations.totpSignupSubtitle,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 350.ms, duration: 400.ms)
                          .slideY(begin: 0.2),
                      const SizedBox(height: 24),

                      // --- Combined Interaction Card ---
                      Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // --- Step 1 ---
                                Text(
                                  appLocalizations.totpSignupStep1Title,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  appLocalizations.totpSignupExplanation,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: InkWell(
                                    onTap: () => tryLaunchUrl(googleStoreUrl),
                                    child: SvgPicture.asset(
                                      googleStoreBadgeAsset,
                                      height: 40,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: Text(
                                    appLocalizations.totpSignupWorksWithLabel,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    InkWell(
                                      onTap: () => tryLaunchUrl(googleStoreUrl),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Tooltip(
                                        message: 'Google Authenticator',
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: SvgPicture.asset(
                                            _kGoogleAuthIcon,
                                            width: 28,
                                            height: 28,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    InkWell(
                                      onTap: () => tryLaunchUrl(authyStoreUrl),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Tooltip(
                                        message: 'Authy',
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: SvgPicture.asset(
                                            _kAuthyIcon,
                                            width: 28,
                                            height: 28,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 32),

                                // --- Step 2 ---
                                Text(
                                  appLocalizations.totpSignupStep2Title,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _openAuthenticator(context, otpAuthUri),
                                  icon: const Icon(Icons.add_link),
                                  label: Text(
                                    appLocalizations
                                        .totpSignupOpenAuthenticatorButton,
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(
                                      double.infinity,
                                      50,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: Text(
                                    appLocalizations.totpSignupOrManual,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: () =>
                                      _copySecretToClipboard(context, ref),
                                  icon: const Icon(Icons.copy_all_outlined),
                                  label: Text(
                                    appLocalizations
                                        .totpSignupCopyKeyManualTooltip,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(
                                      double.infinity,
                                      50,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    side: BorderSide(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 400.ms, duration: 400.ms)
                          .slideY(begin: 0.2),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                child: Column(
                  children: [
                    Text(
                      appLocalizations.totpSignupAfterSetupPrompt,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    WelcomeButton(
                          text: appLocalizations.loginContinueButton,
                          onPressed: () {
                            context.pushNamed(
                              AppRouteNames.totpVerifyPage,
                              extra: TotpVerifyArgs(
                                displayIdentifier: signUpState.phoneNumber,
                                onSuccess: (code) =>
                                    _onVerifyAndRegister(context, ref, code),
                              ),
                            );
                          },
                        )
                        .animate()
                        .fadeIn(delay: 500.ms, duration: 400.ms)
                        .slideY(begin: 0.5),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
