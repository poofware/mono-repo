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
    await Geolocator.openLocationSettings();
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
    await Geolocator.openAppSettings();
    return false;
  }

  // Success when permission is granted for foreground or all-time use.
  return perm == LocationPermission.always ||
         perm == LocationPermission.whileInUse;
  }

