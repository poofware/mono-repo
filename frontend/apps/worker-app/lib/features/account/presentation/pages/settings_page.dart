import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations


// Import the provider
import '../../providers/providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = AppLocalizations.of(context);
    // Watch the state from the provider
    final settings = ref.watch(settingsStateNotifierProvider);

    final bool notificationsEnabled = settings.notificationsEnabled;
    final bool isDarkMode = (settings.themeMode == ThemeMode.dark);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    appLocalizations.settingsPageTitle,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // Notifications Switch
            SwitchListTile(
              title: Text(appLocalizations.settingsPageEnableNotifications),
              value: notificationsEnabled,
              onChanged: (bool newValue) {
                // update via the notifier
                ref.read(settingsStateNotifierProvider.notifier)
                    .setNotificationsEnabled(newValue);
              },
            ),
            // Dark Mode Switch
            SwitchListTile(
              title: Text(appLocalizations.settingsPageDarkMode),
              value: isDarkMode,
              onChanged: (bool newValue) {
                ref.read(settingsStateNotifierProvider.notifier)
                    .setThemeMode(newValue);
              },
            ),
          ],
        ),
      ),
    );
  }
}
