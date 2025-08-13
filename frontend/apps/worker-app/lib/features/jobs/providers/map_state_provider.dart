// worker-app/lib/features/jobs/providers/map_state_provider.dart

// No material imports needed here
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'dart:ui' show IsolateNameServer; // For IsolateNameServer
import 'dart:isolate'; // For SendPort


// --- Top-level constants and helpers for marker creation (accessible by isolate) ---
const String kMarkerTapPortName = 'markerTapPort'; // Port name for tap events

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
  if (inst.property.latitude != 0 || inst.property.longitude != 0) {
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
        consumeTapEvents: true,
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
  String? _selectedLocKey; // track current selected location
  MarkerCacheNotifier(this.ref) : super({});

  /// Public method to replace all markers in the cache.
  void replaceAllMarkers(Map<String, Marker> newMarkers) {
    // If we already have a selection, keep it visually selected by mutating the real marker.
    if (_selectedLocKey != null && newMarkers.containsKey(_selectedLocKey)) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        newMarkers[_selectedLocKey!] = newMarkers[_selectedLocKey!]!.copyWith(
          iconParam: _markerSelectedIcon,
          zIndexIntParam: 1,
        );
      } else {
        newMarkers[_selectedLocKey!] =
            newMarkers[_selectedLocKey!]!.copyWith(iconParam: _markerSelectedIcon);
      }
    }
    state = newMarkers;
  }

  /// Public method to clear all markers from the cache.
  void clearAllMarkers() {
    if (state.isNotEmpty) {
      state = {};
    }
  }

  /// Toggle selection by updating the real marker at that location.
  void updateSelection(String? newSelectedId, String? previousSelectedId) {
    if (state.isEmpty) return;

    final defToLoc = ref.read(definitionIdToLocationKeyProvider);
    final cache = Map<String, Marker>.from(state);

    // Revert previous selection (by explicit previous ID or last known loc key)
    final String? prevLocKey =
        previousSelectedId != null ? defToLoc[previousSelectedId] : _selectedLocKey;
    if (prevLocKey != null && cache.containsKey(prevLocKey)) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        cache[prevLocKey] = cache[prevLocKey]!.copyWith(
          iconParam: _markerDefaultIcon,
          zIndexIntParam: 0,
        );
      } else {
        cache[prevLocKey] =
            cache[prevLocKey]!.copyWith(iconParam: _markerDefaultIcon);
      }
    }

    // Apply new selection
    final String? newLocKey = newSelectedId != null ? defToLoc[newSelectedId] : null;
    if (newLocKey != null && cache.containsKey(newLocKey)) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        cache[newLocKey] = cache[newLocKey]!.copyWith(
          iconParam: _markerSelectedIcon,
          zIndexIntParam: 1,
        );
      } else {
        cache[newLocKey] =
            cache[newLocKey]!.copyWith(iconParam: _markerSelectedIcon);
      }
    }

    _selectedLocKey = newLocKey;
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
