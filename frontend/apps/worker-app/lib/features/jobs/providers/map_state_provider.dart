// worker-app/lib/features/jobs/providers/map_state_provider.dart

import 'package:flutter/foundation.dart';
// No material imports needed here
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'dart:ui' show IsolateNameServer; // For IsolateNameServer
import 'dart:isolate'; // For SendPort


// --- Top-level constants and helpers for marker creation (accessible by isolate) ---
const String kMarkerTapPortName = 'markerTapPort'; // Port name for tap events
const String kSelectedOverlayMarkerId = '__selected_overlay_marker__';

final BitmapDescriptor _markerDefaultIcon =
    BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
final BitmapDescriptor _markerSelectedIcon =
    BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

const LatLng kLosAngelesLatLng = LatLng(34.0522, -118.2437); // Duplicated from HomePage for now, useful as fallback

LatLng _markerPositionIsolateHelper(JobInstance inst) {
  if (inst.buildings.isNotEmpty &&
      inst.buildings.first.latitude != 0 &&
      inst.buildings.first.longitude != 0) {
    return LatLng(
        inst.buildings.first.latitude, inst.buildings.first.longitude);
  }
  // Use AND to ensure both coordinates are valid; prevents bogus positions
  if (inst.property.latitude != 0 && inst.property.longitude != 0) {
    return LatLng(inst.property.latitude, inst.property.longitude);
  }
  return kLosAngelesLatLng; // Fallback position
}

// Rounds to ~0.11 meters at equator; prevents near-overlaps from collapsing
String locationKeyForLatLng(LatLng p) =>
    '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';

// --- Arguments for the compute function ---
class RebuildMarkerArgs {
  final List<DefinitionGroup> definitions;
  final String? currentSelectedId;
  final bool isOnline;
  // Note: The onMarkerTap callback is not passed directly.
  // Instead, communication happens via SendPort/ReceivePort.

  RebuildMarkerArgs({
    required this.definitions,
    required this.currentSelectedId,
    required this.isOnline,
  });
}

// --- Compute function for rebuilding markers in an isolate ---
Map<String, Marker> rebuildAndCreateMarkersIsolate(RebuildMarkerArgs args) {
  final Map<String, Marker> newCache = {};
  final SendPort? mainIsolatePort = IsolateNameServer.lookupPortByName(kMarkerTapPortName);

  if (!args.isOnline) {
    return newCache; // Return empty cache if not online
  }

  for (final d in args.definitions) {
    if (d.instances.isNotEmpty) {
      // Deduplicate by location – only one marker per rounded LatLng
      final pos = _markerPositionIsolateHelper(d.instances.first);
      final key = locationKeyForLatLng(pos);
      if (newCache.containsKey(key)) continue;
      newCache[key] = Marker(
        markerId: MarkerId(key),
        position: pos,
        icon: _markerDefaultIcon,
        // Allow map onTap for pixel-nearest, but also handle direct marker taps
        consumeTapEvents: false,
        onTap: () {
          final SendPort? port = IsolateNameServer.lookupPortByName(kMarkerTapPortName);
          if (port != null) {
            port.send(key);
          }
        },
      );
    }
  }
  return newCache;
}


// --- Providers ---

/// Provider for the ID of the currently selected job definition on the map/carousel.
/// This is for live UI state. For persistence, see `lastSelectedDefinitionIdProvider`.
final selectedDefinitionIdProvider = StateProvider<String?>((ref) => null);

/// Notifier for managing the cache of Marker objects.
/// Its state is now primarily set by HomePage after running a compute function.
class MarkerCacheNotifier extends StateNotifier<Map<String, Marker>> {
  final Ref ref;
  MarkerCacheNotifier(this.ref) : super({});

  String? _currentHighlightedDefId;

  /// Public method to replace all markers in the cache.
  void replaceAllMarkers(Map<String, Marker> newMarkers) {
    // Consider using mapEquals if performance allows and newMarkers might be structurally same but different instance
    // if (!mapEquals(state, newMarkers)) {
    //   state = newMarkers;
    // }
    // Preserve existing overlay marker across rebuilds
    final overlay = state[kSelectedOverlayMarkerId];
    final merged = Map<String, Marker>.from(newMarkers);
    if (overlay != null) {
      merged[kSelectedOverlayMarkerId] = overlay;
    }
    state = merged;
  }

  /// Public method to clear all markers from the cache.
  void clearAllMarkers() {
    if (state.isNotEmpty) {
      state = {};
    }
    _currentHighlightedDefId = null;
  }

  /// Highlights selection using a single overlay marker positioned at the
  /// selected location. Base markers remain unchanged.
  void updateSelection(String? newSelectedId, String? previousSelectedId) {
    if (state.isEmpty) return;
    final cache = Map<String, Marker>.from(state);

    if (newSelectedId == null) {
      cache.remove(kSelectedOverlayMarkerId);
      _currentHighlightedDefId = null;
      state = cache;
      return;
    }

    // Map definition -> location key
    final defToLoc = ref.read(definitionIdToLocationKeyProvider);
    final locKey = defToLoc[newSelectedId];
    if (locKey == null) {
      return;
    }

    // Try to resolve position from cache; if missing, use stored location map
    LatLng? pos = cache[locKey]?.position;
    if (pos == null) {
      final locMap = ref.read(locationKeyToPositionProvider);
      pos = locMap[locKey];
      if (pos == null) {
        return;
      }
    }
    cache[kSelectedOverlayMarkerId] = (cache[kSelectedOverlayMarkerId])?.copyWith(
          positionParam: pos,
          iconParam: _markerSelectedIcon,
          zIndexIntParam: 100,
        ) ??
        Marker(
          markerId: const MarkerId(kSelectedOverlayMarkerId),
          position: pos,
          icon: _markerSelectedIcon,
          zIndexInt: 100,
          consumeTapEvents: false,
        );

    _currentHighlightedDefId = newSelectedId;
    state = cache;
  }
}

/// Provider for the MarkerCacheNotifier.
final jobMarkerCacheProvider =
    StateNotifierProvider<MarkerCacheNotifier, Map<String, Marker>>((ref) {
  return MarkerCacheNotifier(ref);
});

/// NEW provider that only emits when the *reference* of relevant markers might change.
/// It derives its value from jobMarkerCacheProvider.
/// Consumers of this provider get a Set<[Marker]> that is efficient for GoogleMap.
final visibleMarkersProvider = Provider<Set<Marker>>((ref) {
  final cache = ref.watch(jobMarkerCacheProvider); // Map<String, Marker>
  // Return an unmodifiable Set view of the values.
  // This Set instance will be new if `cache` instance changes,
  // but Riverpod handles efficient rebuilds of consumers.
  return Set<Marker>.unmodifiable(cache.values);
});


/// Mapping: definitionId -> locationKey
final definitionIdToLocationKeyProvider =
    StateProvider<Map<String, String>>((ref) => {});

/// Mapping: locationKey -> exact LatLng
final locationKeyToPositionProvider =
    StateProvider<Map<String, LatLng>>((ref) => {});

/// Mapping: locationKey -> definitions located at this coordinate
final locationKeyToDefinitionIdsProvider =
    StateProvider<Map<String, List<String>>>((ref) => {});
