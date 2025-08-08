// worker-app/lib/features/jobs/providers/map_state_provider.dart

import 'package:flutter/foundation.dart';
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
      final isSelected = d.definitionId == args.currentSelectedId;
      newCache[d.definitionId] = Marker(
        markerId: MarkerId(d.definitionId),
        position: _markerPositionIsolateHelper(d.instances.first),
        icon: isSelected ? _markerSelectedIcon : _markerDefaultIcon,
        zIndexInt: isSelected ? 1: 0,
        consumeTapEvents: true,
        onTap: () {
          if (mainIsolatePort != null) {
            mainIsolatePort.send(d.definitionId);
          } else {
            // This case should ideally not happen if the port is registered correctly.
            // Consider logging or a fallback if critical.
            debugPrint("Error: Marker tap port not found in isolate.");
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
  MarkerCacheNotifier() : super({});

  /// Public method to replace all markers in the cache.
  void replaceAllMarkers(Map<String, Marker> newMarkers) {
    // Consider using mapEquals if performance allows and newMarkers might be structurally same but different instance
    // if (!mapEquals(state, newMarkers)) {
    //   state = newMarkers;
    // }
    // For now, direct assignment as compute likely produces a new map instance.
    state = newMarkers;
  }

  /// Public method to clear all markers from the cache.
  void clearAllMarkers() {
    if (state.isNotEmpty) {
      state = {};
    }
  }

  /// Updates the icons for the previously selected and newly selected markers.
  /// This is a lightweight operation and can be called directly.
  void updateSelection(String? newSelectedId, String? previousSelectedId) {
    final newCacheState = Map<String, Marker>.from(state);
    bool changed = false;

    if (previousSelectedId != null && newCacheState.containsKey(previousSelectedId)) {
      final oldMarker = newCacheState[previousSelectedId]!;
      if (oldMarker.icon != _markerDefaultIcon || oldMarker.zIndexInt != 0.0) {
        newCacheState[previousSelectedId] = oldMarker.copyWith(
          iconParam: _markerDefaultIcon,
          zIndexIntParam: 0,
        );
        changed = true;
      }
    }

    if (newSelectedId != null && newCacheState.containsKey(newSelectedId)) {
       final oldMarker = newCacheState[newSelectedId]!;
       if (oldMarker.icon != _markerSelectedIcon || oldMarker.zIndexInt != 1.0) {
        newCacheState[newSelectedId] = oldMarker.copyWith(
          iconParam: _markerSelectedIcon,
          zIndexIntParam: 1,
        );
        changed = true;
      }
    }

    if (changed) {
      state = newCacheState;
    }
  }
}

/// Provider for the MarkerCacheNotifier.
final jobMarkerCacheProvider =
    StateNotifierProvider<MarkerCacheNotifier, Map<String, Marker>>((ref) {
  return MarkerCacheNotifier();
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
