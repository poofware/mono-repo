// worker-app/lib/core/providers/initial_setup_providers.dart
// NEW FILE

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Holds the camera position determined at app boot.
/// - If permissions granted & location fetched: User's location.
/// - If permissions granted & location fetch failed: null (signifying fetch failure).
/// - If permissions not granted: Los Angeles default.
final initialBootCameraPositionProvider = StateProvider<CameraPosition?>((ref) => null);

/// Holds the status of location permission granted at app boot.
final bootTimePermissionGrantedProvider = StateProvider<bool>((ref) => false);

/// Holds the preloaded Google Maps style JSON, loaded during app boot so the
/// first map render doesn't flash while applying style.
final mapStyleJsonProvider = StateProvider<String?>((ref) => null);

/// Tracks whether the primary Home map has mounted at least once. Used to
/// disable the global warm-up map overlay after the real map is ready.
final homeMapMountedProvider = StateProvider<bool>((ref) => false);
