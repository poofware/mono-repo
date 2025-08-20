// worker-app/lib/features/account/presentation/pages/help_and_support_page.dart
// NEW FILE

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/presentation/utils/url_launcher_utils.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';

class HelpAndSupportPage extends ConsumerWidget {
  const HelpAndSupportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // This function handles the logic for launching a URL and showing a snackbar on failure
    Future<void> launch(String url) async {
      final success = await tryLaunchUrl(url);
      if (!success && context.mounted) {
        showAppSnackBar(
          context,
          Text(appLocalizations.urlLauncherCannotLaunch),
        );
      }
    }

    String encoded(String value) => Uri.encodeComponent(value);

    final String supportEmail = 'team@thepoofapp.com';
    final String supportPhone = '256-468-3659'; // Formatted for display
    final String supportPhoneUrl = 'tel:2564683659'; // Unformatted for tel link

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // --- Custom Header ---
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    appLocalizations.helpAndSupportTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // --- Scrollable Content ---
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children:
                    [
                          const SizedBox(height: 16),
                          const Icon(
                                Icons.help_outline, // REPLACED ICON
                                size: 80,
                                color: AppColors.poofColor,
                              )
                              .animate()
                              .fadeIn(delay: 100.ms)
                              .scale(begin: const Offset(0.8, 0.8)),
                          const SizedBox(height: 24),
                          Text(
                            appLocalizations.helpAndSupportTitle,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            appLocalizations.helpPageIntro,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          // --- Primary Email Support Tile ---
                          Card(
                            elevation: 0,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            child: ListTile(
                              onTap: () => launch(
                                'mailto:$supportEmail?subject=${encoded(appLocalizations.emailSubjectGeneralHelp)}',
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 20,
                              ),
                              leading: const Icon(
                                Icons.email_outlined,
                                size: 32,
                                color: AppColors.poofColor,
                              ),
                              title: Text(
                                appLocalizations.emailSupportLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                supportEmail,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondary,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                size: 28,
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          // --- Phone Number Info Box ---
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  appLocalizations.forUrgentIssues,
                                  style: theme.textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                InkWell(
                                  onTap: () => launch(supportPhoneUrl),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.call_outlined,
                                          color: theme.colorScheme.primary,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          supportPhone,
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.2,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]
                        .animate(interval: 80.ms)
                        .fadeIn(duration: 400.ms, delay: 200.ms)
                        .slideY(begin: 0.1, curve: Curves.easeOutCubic),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
