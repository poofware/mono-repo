import 'package:geolocator/geolocator.dart';

/// Ensures the user has granted an adequate location permission and that the
/// device-side “Location” switch is ON.
///
/// Returns `true` when you can safely call `Geolocator.getCurrentPosition()` or
/// `getPositionStream()`.  If it returns `false`, show your own UI telling the
/// user what to do next.
///
/// • [background] – set to `true` when your app needs background location
///   updates (trip tracking, navigation while app in background).
Future<bool> ensureLocationGranted({bool background = false}) async {
  // Check if location services (GPS) are enabled.
  if (!await Geolocator.isLocationServiceEnabled()) {
    // Do not auto-redirect users to Settings. Return false so caller can show UI.
    return false;
  }

  // Check the current runtime permission state, request if needed.
  LocationPermission perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }

  // If you need background updates, prompt again to upgrade While-In-Use → Always.
  if (background && perm == LocationPermission.whileInUse) {
    perm = await Geolocator.requestPermission();
  }

  // Handle the “Don’t ask again” / permanently denied case.
  if (perm == LocationPermission.deniedForever) {
    // Do not auto-redirect users to Settings. Return false so caller can show UI.
    return false;
  }

  // Success when permission is granted for foreground or all-time use.
  return perm == LocationPermission.always ||
      perm == LocationPermission.whileInUse;
}

/// Returns true if the app currently has foreground or all-time location
/// permission. This function does NOT prompt the user.
Future<bool> hasLocationPermission() async {
  final perm = await Geolocator.checkPermission();
  return perm == LocationPermission.always ||
      perm == LocationPermission.whileInUse;
}

/// Returns the OS-reported location accuracy authorization.
///
/// On iOS 14+ and Android 12+, users can grant approximate (reduced) location.
/// This exposes the current status so callers can adapt UX or gate features
/// that require precise location.
Future<LocationAccuracyStatus> getLocationAccuracyStatus() async {
  try {
    return await Geolocator.getLocationAccuracy();
  } catch (_) {
    // On older OS versions or if the platform doesn't support this query,
    // default to precise so we don't block users unnecessarily.
    return LocationAccuracyStatus.precise;
  }
}

/// Convenience helper to check if precise location is currently enabled.
Future<bool> hasPreciseLocation() async {
  final status = await getLocationAccuracyStatus();
  return status == LocationAccuracyStatus.precise;
}
