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
