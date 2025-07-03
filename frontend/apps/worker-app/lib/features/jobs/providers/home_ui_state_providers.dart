// worker-app/lib/features/jobs/providers/home_ui_state_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:poof_worker/features/jobs/presentation/pages/home_page.dart' show kLosAngelesLatLng, kDefaultMapZoom; // For default
import 'package:poof_worker/core/providers/initial_setup_providers.dart';

/// Persists the ID of the last selected job definition on the HomePage map/carousel.
/// Reset on logout.
final lastSelectedDefinitionIdProvider = StateProvider<String?>((ref) {
  ref.keepAlive();
  return null;
});

/// Persists the last known camera position of the map on HomePage.
/// Reset on logout.
final lastMapCameraPositionProvider = StateProvider<CameraPosition?>((ref) {
  ref.keepAlive();
  return null;
});

/// Holds the live, current camera position of the map on HomePage.
/// This is distinct from `lastMapCameraPositionProvider` which is for persistence.
/// HomePage's initialization logic will set this based on boot/persisted values.
final currentMapCameraPositionProvider = StateProvider<CameraPosition>((ref) {
  // This initial value is a fallback. HomePage will set the correct one.
  final bootPosition = ref.watch(initialBootCameraPositionProvider);
  return bootPosition ?? const CameraPosition(target: kLosAngelesLatLng, zoom: kDefaultMapZoom);
});
