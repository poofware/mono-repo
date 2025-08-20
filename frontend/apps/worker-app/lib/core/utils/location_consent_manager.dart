// worker-app/lib/core/utils/location_consent_manager.dart

import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';

/// Persists whether the Android location disclosure screen has been
/// acknowledged/completed by the user.
class LocationConsentManager {
  static const _androidDisclosureCompletedKey =
      'android_location_disclosure_completed_v1';

  // In-memory cache used by router redirect logic (which must be synchronous).
  // null means not yet loaded.
  static bool? cachedAndroidDisclosureComplete;

  static Future<bool> isAndroidDisclosureComplete() async {
    if (!Platform.isAndroid) return true; // iOS/macOS/web: N/A
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_androidDisclosureCompletedKey) ?? false;
    cachedAndroidDisclosureComplete = done;
    return done;
  }

  static Future<void> markAndroidDisclosureComplete() async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_androidDisclosureCompletedKey, true);
    cachedAndroidDisclosureComplete = true;
  }
}
