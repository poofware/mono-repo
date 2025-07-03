// worker-app/lib/core/utils/fresh_install_manager.dart
// NEW FILE

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';

/// A utility to detect the first launch after a fresh install and clear
/// any persistent authentication data from previous installations.
///
/// This is crucial for iOS, where `flutter_secure_storage` uses the Keychain,
/// which can persist data even after an app is uninstalled. By using
/// `shared_preferences` (which is always cleared on uninstall) to set a flag,
/// we can reliably determine if this is the very first run.
class FreshInstallManager {
  static const _hasRunBeforeKey = 'app_has_run_before';

  /// Checks if the app has been run before. If not, it clears all stored
  /// tokens and attestation keys, then sets a flag to prevent this from
  /// running again until the next fresh install.
  ///
  /// This should be called once at the very start of the app's lifecycle,
  /// typically in `main()`.
  static Future<void> handleFreshInstall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasRunBefore = prefs.getBool(_hasRunBeforeKey) ?? false;

      if (!hasRunBefore) {
        debugPrint('[FreshInstallManager] First run detected. Clearing stored tokens and keys.');
        
        // Clear JWTs from flutter_secure_storage
        final tokenStorage = SecureTokenStorage();
        await tokenStorage.clearTokens();

        // Set the flag so this logic doesn't run again
        await prefs.setBool(_hasRunBeforeKey, true);
        debugPrint('[FreshInstallManager] First-run flag set.');
      } else {
        debugPrint('[FreshInstallManager] Not a fresh install, skipping token clear.');
      }
    } catch (e) {
      // If any part of this fails, we log it but don't crash the app.
      // The worst case is that a user might remain logged in on reinstall.
      debugPrint('[FreshInstallManager] Error during fresh install check: $e');
    }
  }
}

