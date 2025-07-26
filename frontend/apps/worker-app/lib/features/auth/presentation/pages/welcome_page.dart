// worker-app/lib/features/auth/presentation/pages/welcome_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations

import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/providers/welcome_video_provider.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/core/providers/localization_provider.dart'; // Import locale provider

class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key});
  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  bool _playHeadline = false;
  // A single flag to prevent spam-tapping either navigation action.
  bool _isNavigating = false;

  // Track the language-button size so the popup can match it
  final GlobalKey _langBtnKey = GlobalKey();
  double? _langBtnWidth;

  // ---- supported locales for picker UI -------------------------------------
  final List<Locale> _supportedPickerLocales = const [
    Locale('en', 'US'),
    Locale('es', 'ES'),
  ];
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _playHeadline = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The video controller is now playing by default from MyApp.
    final videoController = ref.watch(welcomeVideoControllerProvider);
    final appLocalizations = AppLocalizations.of(context);
    final currentLocale = ref.watch(currentLocaleProvider);

    // Find the matching picker locale for initialValue, default to English if not found
    final Locale selectedPickerLocale = _supportedPickerLocales.firstWhere(
      (l) => l.languageCode == currentLocale.languageCode,
      orElse: () => const Locale('en', 'US'),
    );

    // Capture language-button width after first layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _langBtnKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && mounted && _langBtnWidth != box.size.width) {
        setState(() => _langBtnWidth = box.size.width);
      }
    });

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            // ------------------ CENTERED VIDEO (nudged up) ------------------------------
            SafeArea(
              maintainBottomViewPadding: true,
              child: Transform.translate(
                offset: const Offset(0, -40),
                child: Center(
                  child: Padding(
                    padding: AppConstants.kDefaultPadding,
                    child: (videoController != null &&
                            videoController.value.isInitialized)
                        ? AspectRatio(
                            aspectRatio: videoController.value.aspectRatio,
                            child: Transform.scale(
                              scale: 1.1,
                              child:
                                  ClipRect(child: VideoPlayer(videoController)),
                            ))
                        : AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Container(
                              color: Colors.grey[200],
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.videocam_off,
                                        size: 48, color: Colors.grey),
                                    const SizedBox(height: 8),
                                    Text(appLocalizations.welcomeVideoNotLoaded,
                                        textAlign: TextAlign.center),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),

            // ---------------- BOTTOM HEADLINE & ACTIONS --------------------
            SafeArea(
              maintainBottomViewPadding: true,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: 15.0,
                    left: AppConstants.kDefaultPadding.left,
                    right: AppConstants.kDefaultPadding.right,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // headline
                      Column(
                        children: [
                          Text(
                            appLocalizations.welcomeNewToPoof,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 1),
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              Text(
                                appLocalizations.welcomeSloganPart1,
                                style: const TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w700),
                              ),
                              ...[
                                appLocalizations.welcomeSloganTrash,
                                appLocalizations.welcomeSloganTo,
                                appLocalizations.welcomeSloganCash,
                              ].asMap().entries.map((e) {
                                final word = e
                                    .value; // Already includes punctuation/spacing from ARB
                                return Text(
                                  word,
                                  style: const TextStyle(
                                      fontSize: 22, fontWeight: FontWeight.w700),
                                )
                                    .animate(
                                      autoPlay: false,
                                      target: _playHeadline ? 1 : 0,
                                    )
                                    .slideY(
                                      begin: -1,
                                      end: 0,
                                      duration: 400.ms,
                                      delay: (e.key * 300).ms,
                                      curve: Curves.easeOutBack,
                                    )
                                    .fadeIn(
                                      duration: 400.ms,
                                      delay: (e.key * 300).ms,
                                    );
                              }),
                            ],
                          ),
                        ],
                      ),
            
                      const SizedBox(
                          height: AppConstants.kDefaultVerticalSpacing * 1.2),
            
                      // login button
                      WelcomeButton(
                        text: appLocalizations.welcomeLoginButton,
                        fontSize: 18,
                        // no isLoading → no spinner, but we still block repeat taps
                        onPressed: () {
                          if (_isNavigating) return;       // lock‑out
                          setState(() => _isNavigating = true);
                          // clear the flag once the route is popped
                          context.pushNamed(AppRouteNames.loginPage).then((_) {
                            if (mounted) setState(() => _isNavigating = false);
                          });
                        },
                      ),
            
                      const SizedBox(
                          height: AppConstants.kDefaultVerticalSpacing),
            
                      // create-account link
                      GestureDetector(
                        onTap: () {
                          if (_isNavigating) return;
                          setState(() => _isNavigating = true);
                          context.pushNamed(AppRouteNames.createAccountPage).then((_) {
                            if (mounted) setState(() => _isNavigating = false);
                          });
                        },
                        child: Text(
                          appLocalizations.welcomeCreateAccountButton,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _isNavigating
                                ? AppColors.buttonBackground
                                    .withValues(alpha: 0.5)
                                : AppColors.buttonBackground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ----------------- LOCALE SELECTOR (TOP-CENTER) ------------------
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: _buildLanguageSelector(context, selectedPickerLocale),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // locale picker widget
  Widget _buildLanguageSelector(
      BuildContext context, Locale currentSelectedUILocale) {
    return PopupMenuButton<Locale>(
      key: _langBtnKey,
      initialValue: currentSelectedUILocale,
      constraints: _langBtnWidth == null
          ? null
          : BoxConstraints.tightFor(width: _langBtnWidth),
      onSelected: (Locale locale) {
        ref.read(currentLocaleProvider.notifier).state =
            Locale(locale.languageCode);
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: AppColors.buttonBackground,
      itemBuilder: (context) => _supportedPickerLocales
          .map(
            (locale) => PopupMenuItem<Locale>(
              value: locale,
              child: Text(
                _localeLabel(locale),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.buttonBackground,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              _localeLabel(currentSelectedUILocale),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _localeLabel(Locale locale) {
    switch (locale.languageCode) {
      case 'es':
        return 'ES';
      case 'en':
      default:
        return 'EN';
    }
  }
}
