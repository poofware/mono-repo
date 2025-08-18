// worker-app/lib/features/jobs/presentation/pages/home_page.dart

import 'dart:async'; // For Timer
import 'dart:isolate'; // For ReceivePort
import 'dart:ui' show IsolateNameServer; // For IsolateNameServer

import 'package:flutter/foundation.dart'; // For compute
import 'package:flutter/gestures.dart'; // For kTouchSlop
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:collection/collection.dart'; // For firstWhereOrNull
import 'package:poof_worker/l10n/generated/app_localizations.dart';

import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/utils/location_permissions.dart';
import 'package:poof_worker/features/account/presentation/pages/worker_drawer_page.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart'
    show DefinitionGroup, JobInstance, groupOpenJobs;
import 'package:poof_worker/features/jobs/presentation/widgets/job_definition_carousel_widget.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/go_online_button_widget.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/jobs_sheet_widget.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';
import 'package:poof_worker/core/providers/initial_setup_providers.dart';
import 'package:poof_worker/features/jobs/providers/home_ui_state_providers.dart';
import 'package:poof_worker/features/jobs/providers/map_state_provider.dart';
import 'package:poof_worker/features/jobs/providers/tap_ripple_provider.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/tap_ripple_overlay.dart';
import 'package:poof_worker/core/providers/ui_messaging_provider.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
// removed dynamic overlay provider usage

/// ─────────────────────────────────────────────────────────────────────────
///  P R O V I D E R S (Jobs List Related)
/// ─────────────────────────────────────────────────────────────────────────

final jobsSortByProvider = StateProvider<String>((_) => 'distance');
final jobsSearchQueryProvider = StateProvider<String>((_) => '');

final filteredDefinitionsProvider = Provider<List<DefinitionGroup>>((ref) {
  final jobsState = ref.watch(jobsNotifierProvider);
  final sortBy = ref.watch(jobsSortByProvider);
  final query = ref.watch(jobsSearchQueryProvider).trim().toLowerCase();

  bool matchesQuery(DefinitionGroup d) {
    if (query.isEmpty) return true;

    final searchable = buildSearchableDefinitionText(d);

    return fuzzyMatch(searchable, query);
  }

  final list = groupOpenJobs(jobsState.openJobs).where(matchesQuery).toList();

  // Primary sort for the sheet is user-selected. We will keep this behavior
  // here and build a separate provider for the carousel to ensure a stable
  // property/building sort there.
  int byPropThenBldgThenId(DefinitionGroup a, DefinitionGroup b) {
    final c1 = a.propertyName.compareTo(b.propertyName);
    if (c1 != 0) return c1;
    final c2 = a.buildingSubtitle.compareTo(b.buildingSubtitle);
    if (c2 != 0) return c2;
    return a.definitionId.compareTo(b.definitionId);
  }

  int byDistance(DefinitionGroup a, DefinitionGroup b) {
    final c = a.distanceMiles.compareTo(b.distanceMiles);
    if (c != 0) return c;
    return byPropThenBldgThenId(a, b);
  }

  int byPay(DefinitionGroup a, DefinitionGroup b) {
    final c = b.pay.compareTo(a.pay);
    if (c != 0) return c;
    return byPropThenBldgThenId(a, b);
  }

  switch (sortBy) {
    case 'pay':
      list.sort(byPay);
      break;
    case 'distance':
      list.sort(byDistance);
      break;
    default:
      list.sort(byPropThenBldgThenId);
  }
  return list;
});

/// Dedicated provider for the carousel order: always property, then building,
/// then definitionId as a deterministic tie-breaker. This ensures that cards
/// for the same property/building stay adjacent in the carousel regardless of
/// the sheet's selected sort mode.
final carouselDefinitionsProvider = Provider<List<DefinitionGroup>>((ref) {
  final filtered = ref.watch(filteredDefinitionsProvider);
  final list = [...filtered];
  list.sort((a, b) {
    final c1 = a.propertyName.compareTo(b.propertyName);
    if (c1 != 0) return c1;
    final c2 = a.buildingSubtitle.compareTo(b.buildingSubtitle);
    if (c2 != 0) return c2;
    return a.definitionId.compareTo(b.definitionId);
  });
  return list;
});

bool fuzzyMatch(String text, String query) {
  if (query.isEmpty) return true;
  int tIndex = 0;
  int qIndex = 0;
  while (tIndex < text.length && qIndex < query.length) {
    if (text[tIndex] == query[qIndex]) {
      qIndex++;
    }
    tIndex++;
  }
  return qIndex == query.length;
}

String buildSearchableDefinitionText(DefinitionGroup d) {
  return <String>[
    d.propertyName,
    d.propertyAddress,
    d.buildingSubtitle,
    ...d.instances.expand((i) => i.buildings.map((b) => b.name)),
  ].join(' ').toLowerCase();
}

/// ─────────────────────────────────────────────────────────────────────────
///  H O M E  P A G E  C O N S T A N T S
/// ─────────────────────────────────────────────────────────────────────────

const kDefaultMapZoom = 14.5;
const kLosAngelesLatLng = LatLng(34.0522, -118.2437);
const kSanFranciscoLatLng = LatLng(37.7749, -122.4194);
const kGenericFallbackLatLng = LatLng(0.0, 0.0);
const kGenericFallbackZoom = 2.0;

Duration _cameraPanDuration = const Duration(
  milliseconds: 350,
); // Used for UI animations like sheet & carousel

// Throttle duration for marker UI updates
const Duration _markerUiThrottleDuration = Duration(milliseconds: 150);

/// ─────────────────────────────────────────────────────────────────────────
///  H O M E  P A G E
/// ─────────────────────────────────────────────────────────────────────────
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  // Keys to measure overlay heights for dynamic max sheet size
  final GlobalKey _goOnlineKey = GlobalKey();
  final GlobalKey _menuButtonKey = GlobalKey();
  final GlobalKey _locButtonKey = GlobalKey();

  // Reverted back to Flutter's native DraggableScrollableController
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  late final PageController _carouselPageController = PageController(
    viewportFraction: 0.9,
  );
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  GoogleMapController? _mapController;
  CameraPosition? _lastCameraMove; // Last position reported by onCameraMove

  String _mapStyle = '';
  bool _locationPermissionOK = false;
  double _carouselOpacity = 1.0;
  bool _ignoreNextPageChange = false;
  bool _isSnappingToLocation = false;
  bool _isSearchVisible = false;
  bool _isAnimatingSheet =
      false; // Flag to prevent race conditions during sheet animation.

  List<JobInstance>? _previousOpenJobsIdentity;
  bool _isInitialLoad = true;

  // For marker tap communication from isolate
  final ReceivePort _markerTapReceivePort = ReceivePort();
  // Timer for throttling marker updates
  Timer? _markerUpdateThrottleTimer;
  // Warm-up subscription to keep a recent location cached by the OS
  StreamSubscription<Position>? _positionWarmupSub;

  // ---- Tap-vs-Drag/Hold helpers for ripple effect ----
  static const _quickTapMax = Duration(milliseconds: 180);
  Offset? _tapStartPosition;
  int? _tapPointerId;
  DateTime? _tapStartTime;
  bool _tapCancelled = false;
  // ----------------------------------------------------

  // Cached sheet size bounds for fraction calculations
  double _cachedMinSheetSize = 0.0;
  double _cachedMaxSheetSize = 1.0;
  // removed dynamic overlay/sheet metrics

  List<DefinitionGroup> _defs() => ref.read(carouselDefinitionsProvider);
  String? _selectedDefId() => ref.read(selectedDefinitionIdProvider);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _locationPermissionOK = ref.read(bootTimePermissionGrantedProvider);
      final initialBootCam = ref.read(initialBootCameraPositionProvider);
      ref.read(currentMapCameraPositionProvider.notifier).state =
          initialBootCam ??
          const CameraPosition(
            target: kSanFranciscoLatLng,
            zoom: kDefaultMapZoom,
          );
      _lastCameraMove = ref.read(currentMapCameraPositionProvider);
      _initializePage();
      // removed dynamic overlay computation
    });

    _sheetController.addListener(_onSheetSizeChanged);

    if (IsolateNameServer.lookupPortByName(kMarkerTapPortName) == null) {
      IsolateNameServer.registerPortWithName(
        _markerTapReceivePort.sendPort,
        kMarkerTapPortName,
      );
    }
    _markerTapReceivePort.listen(_handleMarkerTapFromIsolate);

    // Prefer preloaded style to avoid flash when the map first attaches
    final preloaded = ref.read(mapStyleJsonProvider);
    if (preloaded != null && preloaded.isNotEmpty) {
      _mapStyle = preloaded;
    } else {
      rootBundle.loadString('assets/jsons/map_style.json').then((style) {
        if (mounted) {
          setState(() => _mapStyle = style);
        }
      });
    }

    // Start a lightweight location stream to keep the OS cache warm.
    // This helps make on-demand fixes faster.
    _positionWarmupSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        distanceFilter: 50, // only when user moves meaningfully
      ),
    ).listen((_) {
      // No-op: Allow OS to maintain a fresh last-known position.
    }, onError: (_) {
      // Ignore stream errors; on-demand fetch will handle errors.
    });
  }
  // removed _recomputeOverlayConstraints


  CameraPosition _currentLiveCameraPos() =>
      ref.read(currentMapCameraPositionProvider);

  /// Handles marker tap events sent from the isolate.
  void _handleMarkerTapFromIsolate(dynamic message) {
    if (message is String) {
      final locationKey = message;
      final currentFilteredDefs = ref.read(filteredDefinitionsProvider);
      final locToDefs = ref.read(locationKeyToDefinitionIdsProvider);
      final idsAtLoc = locToDefs[locationKey];
      if (idsAtLoc != null && idsAtLoc.isNotEmpty) {
        final targetDef = currentFilteredDefs.firstWhereOrNull(
          (d) => d.definitionId == idsAtLoc.first,
        );
        if (targetDef != null) {
          final idx = currentFilteredDefs.indexOf(targetDef);
          if (idx != -1) {
            _selectDefinition(
              targetDef,
              idx,
              fromUserInteraction: true,
              animateMap: false,
            );
          }
        }
      }
    }
  }

  /// Throttled wrapper for updating all markers.
  void _updateMarkerCacheForAllDefsThrottled() {
    if (_markerUpdateThrottleTimer?.isActive ?? false) {
      _markerUpdateThrottleTimer!.cancel();
    }
    _markerUpdateThrottleTimer = Timer(_markerUiThrottleDuration, () {
      if (mounted) {
        _performFullMarkerUpdate();
      }
    });
  }

  /// Performs the actual marker update, potentially using a compute isolate.
  Future<void> _performFullMarkerUpdate() async {
    if (!mounted) return;

    final currentFilteredDefs = ref.read(filteredDefinitionsProvider);
    final currentSelectedId = ref.read(selectedDefinitionIdProvider);
    final isOnline = ref.read(jobsNotifierProvider).isOnline;

    final args = RebuildMarkerArgs(
      definitions: currentFilteredDefs,
      currentSelectedId: currentSelectedId,
      isOnline: isOnline,
    );

    try {
      final Map<String, Marker> newMarkerMap = await compute(
        rebuildAndCreateMarkersIsolate,
        args,
      );
      if (mounted) {
        // Build dedupe maps: definition -> location key, and location -> ids
        final defToLoc = <String, String>{};
        final locToPos = <String, LatLng>{};
        final locToDefs = <String, List<String>>{};
        for (final d in currentFilteredDefs) {
          if (d.instances.isEmpty) continue;
          final inst = d.instances.first;
          LatLng pos;
          if (inst.buildings.isNotEmpty &&
              inst.buildings.first.latitude != 0 &&
              inst.buildings.first.longitude != 0) {
            pos = LatLng(inst.buildings.first.latitude, inst.buildings.first.longitude);
          } else if (inst.property.latitude != 0 || inst.property.longitude != 0) {
            pos = LatLng(inst.property.latitude, inst.property.longitude);
          } else {
            pos = kLosAngelesLatLng;
          }
          final key = locationKeyForLatLng(pos);
          defToLoc[d.definitionId] = key;
          locToPos[key] = pos;
          locToDefs.putIfAbsent(key, () => <String>[]).add(d.definitionId);
        }
        ref.read(definitionIdToLocationKeyProvider.notifier).state = defToLoc;
        ref.read(locationKeyToPositionProvider.notifier).state = locToPos;
        ref.read(locationKeyToDefinitionIdsProvider.notifier).state = locToDefs;

        ref.read(jobMarkerCacheProvider.notifier).replaceAllMarkers(newMarkerMap);
        // Re-apply highlight if a selection already exists, since cache was replaced
        final selectedId = ref.read(selectedDefinitionIdProvider);
        if (selectedId != null) {
          ref
              .read(jobMarkerCacheProvider.notifier)
              .updateSelection(selectedId, null);
        }
      }
    } catch (e, s) {
      debugPrint("Error during marker computation: $e\n$s");
      if (mounted && isOnline) {
        ref.read(jobMarkerCacheProvider.notifier).clearAllMarkers();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionWarmupSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _sheetController.removeListener(_onSheetSizeChanged);
    _carouselPageController.dispose();
    _mapController?.dispose();
    IsolateNameServer.removePortNameMapping(kMarkerTapPortName);
    _markerTapReceivePort.close();
    _markerUpdateThrottleTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      if (mounted) {
        ref.read(lastSelectedDefinitionIdProvider.notifier).state =
            _selectedDefId();
        ref.read(lastMapCameraPositionProvider.notifier).state =
            _currentLiveCameraPos();
      }
    }
  }

  double _computeMinSheetSize(BuildContext ctx) {
    const tabBarHeight = kTextTabBarHeight; // 48 px
    const containerPaddingVertical = 16.0 * 2; // 32 px
    const sortRefreshRowHeight = 59.2; // adjusted height
    final bottomInset = MediaQuery.of(ctx).padding.bottom;
    final totalScreenHeight = MediaQuery.of(ctx).size.height;

    final pixels =
        tabBarHeight +
        containerPaddingVertical +
        sortRefreshRowHeight +
        bottomInset;

    return pixels / totalScreenHeight;
  }

  /// 0 → sheet collapsed (min) … 1 → fully open (max)
  double _sheetFraction() {
    if (!_sheetController.isAttached) return 0.0;
    return ((_sheetController.size - _cachedMinSheetSize) /
            (_cachedMaxSheetSize - _cachedMinSheetSize))
        .clamp(0.0, 1.0);
  }

  Future<void> _initializePage() async {
    await _checkLocationAndCamera(isResuming: false);
    if (mounted) {
      _updateMarkerCacheForAllDefsThrottled();
    }
  }

  Future<void> _checkLocationAndCamera({required bool isResuming}) async {
    if (!mounted) return;

    final storedPersistedCam = ref.read(lastMapCameraPositionProvider);
    if (!isResuming && storedPersistedCam != null) {
      ref.read(currentMapCameraPositionProvider.notifier).state =
          storedPersistedCam;
      _moveOrAnimateMapToPosition(storedPersistedCam, animate: false);
      if (mounted) _restoreSelection();
      return;
    }

    final permissionGranted = await ensureLocationGranted(background: false);
    if (!mounted) return;
    setState(() => _locationPermissionOK = permissionGranted);

    CameraPosition camToSet;
    final bootCam = ref.read(initialBootCameraPositionProvider);
    final bootPerms = ref.read(bootTimePermissionGrantedProvider);
    final useBoot =
        !isResuming && bootCam != null && bootPerms && permissionGranted;

    if (useBoot) {
      camToSet = bootCam;
    } else if (permissionGranted) {
      // Try last-known first for a fast snap
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        camToSet = CameraPosition(
          target: LatLng(lastKnown.latitude, lastKnown.longitude),
          zoom: kDefaultMapZoom,
        );
        // Kick off a background refine to a fresh fix
        // (ignore result if it fails or times out)
        unawaited(_refineLocationInBackground());
      } else {
        // Quick, balanced attempt first
        try {
          final posBalanced = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 3),
            ),
          );
          camToSet = CameraPosition(
            target: LatLng(posBalanced.latitude, posBalanced.longitude),
            zoom: kDefaultMapZoom,
          );
          // Optionally refine further (silent)
          unawaited(_refineLocationInBackground());
        } catch (_) {
          try {
            final posHigh = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 7),
              ),
            );
            camToSet = CameraPosition(
              target: LatLng(posHigh.latitude, posHigh.longitude),
              zoom: kDefaultMapZoom,
            );
          } catch (_) {
            camToSet = storedPersistedCam ??
                const CameraPosition(
                  target: kGenericFallbackLatLng,
                  zoom: kGenericFallbackZoom,
                );
          }
        }
      }
    } else {
      if (!mounted) return;
      camToSet = const CameraPosition(
        target: kSanFranciscoLatLng,
        zoom: kDefaultMapZoom,
      );
    }

    if (isResuming && storedPersistedCam != null) {
      camToSet = storedPersistedCam;
    }

    if (mounted) {
      ref.read(currentMapCameraPositionProvider.notifier).state = camToSet;
      _moveOrAnimateMapToPosition(camToSet, animate: !isResuming);
      _restoreSelection();
    }
  }

  void _moveOrAnimateMapToPosition(
    CameraPosition newPosition, {
    required bool animate,
  }) {
    if (!mounted) return;

    final currentLivePos = _currentLiveCameraPos();
    if (currentLivePos != newPosition) {
      ref.read(currentMapCameraPositionProvider.notifier).state = newPosition;
    }
    ref.read(lastMapCameraPositionProvider.notifier).state = newPosition;
    _lastCameraMove = newPosition;

    if (_mapController == null) return;

    if (animate) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(newPosition),
        duration: const Duration(milliseconds: 150),
      );
    } else {
      _mapController!.moveCamera(CameraUpdate.newCameraPosition(newPosition));
    }
  }

  void _applyCameraPositionFromIdle(CameraPosition camFromIdle) {
    if (!mounted) return;

    final currentLivePos = _currentLiveCameraPos();
    if (currentLivePos != camFromIdle) {
      ref.read(currentMapCameraPositionProvider.notifier).state = camFromIdle;
    }
    ref.read(lastMapCameraPositionProvider.notifier).state = camFromIdle;
    _lastCameraMove = camFromIdle;
  }

  /// Attempts to get a fresher fix in the background and gently refines the camera.
  Future<void> _refineLocationInBackground() async {
    try {
      // First, try balanced quickly
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
      if (!mounted) return;
      final cam = CameraPosition(
        target: LatLng(pos.latitude, pos.longitude),
        zoom: _mapController != null
            ? await _mapController!.getZoomLevel()
            : kDefaultMapZoom,
      );
      _moveOrAnimateMapToPosition(cam, animate: true);
      return;
    } catch (_) {
      // Fall through to high accuracy attempt
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 7),
        ),
      );
      if (!mounted) return;
      final cam = CameraPosition(
        target: LatLng(pos.latitude, pos.longitude),
        zoom: _mapController != null
            ? await _mapController!.getZoomLevel()
            : kDefaultMapZoom,
      );
      _moveOrAnimateMapToPosition(cam, animate: true);
    } catch (_) {
      // Ignore error; keep previous camera
    }
  }

  Future<void> _snapToUserLocation() async {
    if (!_locationPermissionOK || _isSnappingToLocation) return;
    if (!mounted) return;
    setState(() => _isSnappingToLocation = true);

    // Capture context before async gap
    final BuildContext capturedContext = context;

    try {
      // 1) Try last-known for an instant snap
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final zoom = _mapController != null
            ? await _mapController!.getZoomLevel()
            : kDefaultMapZoom;
        final cam = CameraPosition(
          target: LatLng(lastKnown.latitude, lastKnown.longitude),
          zoom: zoom,
        );
        _moveOrAnimateMapToPosition(cam, animate: true);
        if (mounted) setState(() => _isSnappingToLocation = false);
        // 2) Refine silently in background
        unawaited(_refineLocationInBackground());
        return;
      }

      // 3) No last-known: quick balanced attempt
      try {
        final posBalanced = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 3),
          ),
        );
        final zoom = _mapController != null
            ? await _mapController!.getZoomLevel()
            : kDefaultMapZoom;
        final cam = CameraPosition(
          target: LatLng(posBalanced.latitude, posBalanced.longitude),
          zoom: zoom,
        );
        _moveOrAnimateMapToPosition(cam, animate: true);
        if (mounted) setState(() => _isSnappingToLocation = false);
        // Optional refine silently
        unawaited(_refineLocationInBackground());
        return;
      } catch (_) {
        // Fall through to high accuracy below
      }

      // 4) High-accuracy fallback with modest timeout
      final posHigh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 7),
        ),
      );
      final zoom = _mapController != null
          ? await _mapController!.getZoomLevel()
          : kDefaultMapZoom;
      final cam = CameraPosition(
        target: LatLng(posHigh.latitude, posHigh.longitude),
        zoom: zoom,
      );
      _moveOrAnimateMapToPosition(cam, animate: true);
    } catch (e) {
      if (!capturedContext.mounted) return;
      showAppSnackBar(
        capturedContext,
        Text(
          AppLocalizations.of(
            capturedContext,
          ).homePageCouldNotGetLocation(e.toString()),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSnappingToLocation = false);
    }
  }

  void _restoreSelection() {
    if (!mounted) return;
    final defs = _defs();
    if (defs.isEmpty) {
      if (_selectedDefId() != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(selectedDefinitionIdProvider.notifier).state = null;
          }
        });
      }
      return;
    }

    DefinitionGroup target;
    final persistedId = ref.read(lastSelectedDefinitionIdProvider);

    if (persistedId != null) {
      target = defs.firstWhere(
        (d) => d.definitionId == persistedId,
        orElse: () => defs.first,
      );
    } else {
      target = defs.first;
    }

    final idx = defs.indexOf(target);
    if (idx != -1) {
      _selectDefinition(
        target,
        idx,
        fromUserInteraction: false,
        animateMap: true,
      );
    }
  }

  void _selectDefinition(
    DefinitionGroup def,
    int idx, {
    required bool fromUserInteraction,
    required bool animateMap,
  }) {
    if (!mounted) return;
    final currentSelectedId = _selectedDefId();

    void updateProviders() {
      if (!mounted) return;
      if (currentSelectedId != def.definitionId) {
        ref.read(selectedDefinitionIdProvider.notifier).state =
            def.definitionId;
      }

      if (fromUserInteraction) {
        ref.read(lastSelectedDefinitionIdProvider.notifier).state =
            def.definitionId;
      }
    }

    if (!fromUserInteraction) {
      WidgetsBinding.instance.addPostFrameCallback((_) => updateProviders());
    } else {
      updateProviders();
    }

    if (_carouselPageController.hasClients &&
        _carouselPageController.page?.round() != idx) {
      if (fromUserInteraction && animateMap) {
        _ignoreNextPageChange = true;
        _carouselPageController.animateToPage(
          idx,
          duration: _cameraPanDuration,
          curve: Curves.easeInOut,
        );
      } else {
        _ignoreNextPageChange = true;
        _carouselPageController.jumpToPage(idx);
      }
    }

    if (animateMap && def.instances.isNotEmpty) {
      if (_mapController != null) {
        LatLng targetPosition;
        final inst = def.instances.first;
        if (inst.buildings.isNotEmpty &&
            inst.buildings.first.latitude != 0 &&
            inst.buildings.first.longitude != 0) {
          final building = inst.buildings.first;
          targetPosition = LatLng(building.latitude, building.longitude);
        } else if (inst.property.latitude != 0 &&
            inst.property.longitude != 0) {
          targetPosition = LatLng(
            inst.property.latitude,
            inst.property.longitude,
          );
        } else {
          targetPosition = kLosAngelesLatLng;
        }
        final targetCameraPos = CameraPosition(
          target: targetPosition,
          zoom: _currentLiveCameraPos().zoom,
        );
        _moveOrAnimateMapToPosition(targetCameraPos, animate: true);
      }
    }
  }

  // Removed legacy per-frame page sync; selection listener now handles this.

  // Listener for sheet size changes; also handles hiding the search bar.
  void _onSheetSizeChanged() {
    if (!mounted || _isAnimatingSheet) return;

    // Carousel opacity logic
    final opacity = _sheetFraction() <= 0.3 ? 1.0 : 0.0;

    // Search bar visibility logic
    final bool shouldHideSearch = _isSearchVisible && _sheetFraction() < 0.4;

    if (_carouselOpacity != opacity || shouldHideSearch) {
      setState(() {
        if (_carouselOpacity != opacity) {
          _carouselOpacity = opacity;
        }
        if (shouldHideSearch) {
          _isSearchVisible = false;
          _searchController.clear();
          ref.read(jobsSearchQueryProvider.notifier).state = '';
          _searchFocusNode.unfocus(); // Dismiss keyboard
        }
      });
    }
  }

  void _onMapPaneCreated(GoogleMapController controller) {
    _mapController = controller;
    if (mounted) {
      final liveCamPos = _currentLiveCameraPos();
      _mapController!.moveCamera(CameraUpdate.newCameraPosition(liveCamPos));
      // Signal that the main Home map is mounted so any warm-up overlay can stop.
      ref.read(homeMapMountedProvider.notifier).state = true;
      _restoreSelection();

      // Ensure initial highlighted overlay for first definition on first mount
      final defs = _defs();
      if (defs.isNotEmpty) {
        final selectedId = _selectedDefId() ?? defs.first.definitionId;
        if (_selectedDefId() == null) {
          ref.read(selectedDefinitionIdProvider.notifier).state = selectedId;
        }
        ref.read(jobMarkerCacheProvider.notifier).updateSelection(selectedId, null);
      }
    }
  }

  void _onCameraMove(CameraPosition cam) {
    _lastCameraMove = cam;
  }

  void _onCameraMoveStarted() {}

  void _onCameraIdle() {
    if (_lastCameraMove != null && mounted) {
      _applyCameraPositionFromIdle(_lastCameraMove!);
    }
  }

  // Undo map onTap behavior to restore original; leave no-op
  Future<void> _onMapTap(LatLng tapLatLng) async {}

  void _handleViewOnMapFromSheet(DefinitionGroup definition) {
    if (!mounted) return;
    _sheetController.animateTo(
      _computeMinSheetSize(context),
      duration: _cameraPanDuration,
      curve: Curves.easeOutCubic,
    );
    final idx = _defs().indexOf(definition);
    _selectDefinition(
      definition,
      idx,
      fromUserInteraction: true,
      animateMap: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // removed dynamic recompute

    // --- Post-Boot Error Listener ---
    ref.listen<List<Object>>(postBootErrorProvider, (previous, next) {
      if (next.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            for (final error in next) {
              final message = userFacingMessageFromObject(context, error);
              showAppSnackBar(
                context,
                Text(message),
                displayDuration: const Duration(seconds: 5),
              );
            }
            ref.read(postBootErrorProvider.notifier).state = [];
          }
        });
      }
    });

    ref.listen<List<DefinitionGroup>>(filteredDefinitionsProvider, (
      previous,
      next,
    ) {
      _updateMarkerCacheForAllDefsThrottled();
    });

    // Keep the visible carousel page aligned to the current selection whenever
    // the carousel's ordering changes (e.g., as pages load or sorts update).
    ref.listen<List<DefinitionGroup>>(carouselDefinitionsProvider, (
      previous,
      next,
    ) {
      final selectedId = ref.read(selectedDefinitionIdProvider);
      if (selectedId == null || !_carouselPageController.hasClients) return;
      final idx = next.indexWhere((d) => d.definitionId == selectedId);
      if (idx != -1 && _carouselPageController.page?.round() != idx) {
        _ignoreNextPageChange = true;
        _carouselPageController.jumpToPage(idx);
      }
    });

    ref.listen<String?>(selectedDefinitionIdProvider, (
      previousSelectedId,
      newSelectedId,
    ) {
      // Keep marker highlight in sync
      ref
          .read(jobMarkerCacheProvider.notifier)
          .updateSelection(newSelectedId, previousSelectedId);

      // Also keep the carousel page aligned to the selected definition, but
      // only when an actual selection change occurs.
      if (newSelectedId != null && _carouselPageController.hasClients) {
        final defsForSync = ref.read(carouselDefinitionsProvider);
        final targetIdx =
            defsForSync.indexWhere((d) => d.definitionId == newSelectedId);
        if (targetIdx != -1 &&
            _carouselPageController.page?.round() != targetIdx) {
          _ignoreNextPageChange = true;
          _carouselPageController.jumpToPage(targetIdx);
        }
      }
    });

    final jobsState = ref.watch(jobsNotifierProvider);
    final newOpenJobs = jobsState.openJobs;
    final filteredDefs = ref.watch(filteredDefinitionsProvider);
    final carouselDefs = ref.watch(carouselDefinitionsProvider);
    final liveCameraPosition = ref.watch(currentMapCameraPositionProvider);
    final appLocalizations = AppLocalizations.of(context);

    final bool openJobsListActuallyChanged = shouldRecenterOnOpenJobsChange(
      _previousOpenJobsIdentity,
      newOpenJobs,
    );
    final bool isFirstTimeLoadingJobs =
        _isInitialLoad && newOpenJobs.isNotEmpty;

    if ((openJobsListActuallyChanged || isFirstTimeLoadingJobs) &&
        newOpenJobs.isNotEmpty) {
      // Choose initial selection from the distance-sorted filtered list (closest first)
      final distanceSortedDefs = ref.read(filteredDefinitionsProvider);
      if (distanceSortedDefs.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            // Auto-select first def and ensure overlay appears immediately
            final firstDef = distanceSortedDefs.first;
            // Find its index in the carousel ordering to align the page.
            final carouselDefsNow = ref.read(carouselDefinitionsProvider);
            final idxInCarousel = carouselDefsNow
                .indexWhere((d) => d.definitionId == firstDef.definitionId);
            final safeIdx = idxInCarousel == -1 ? 0 : idxInCarousel;
            _selectDefinition(
              firstDef,
              safeIdx,
              fromUserInteraction: false,
              animateMap: true,
            );
            ref
                .read(jobMarkerCacheProvider.notifier)
                .updateSelection(firstDef.definitionId, null);
            if (_isInitialLoad) {
              _isInitialLoad = false;
            }
          }
        });
      }
    }
    _previousOpenJobsIdentity = newOpenJobs;

    ref.listen<List<DefinitionGroup>>(filteredDefinitionsProvider, (
      previousFiltered,
      nextFiltered,
    ) {
      final currentSelectedId = ref.read(selectedDefinitionIdProvider);
      if (nextFiltered.isEmpty && currentSelectedId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(selectedDefinitionIdProvider.notifier).state = null;
          }
        });
      }
      if (previousFiltered != null &&
          currentSelectedId != null &&
          nextFiltered.isNotEmpty &&
          !nextFiltered.any((def) => def.definitionId == currentSelectedId) &&
          !openJobsListActuallyChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _restoreSelection();
          }
        });
      }
      _updateMarkerCacheForAllDefsThrottled();
    });

    ref.listen<bool>(jobsNotifierProvider.select((s) => s.isOnline), (
      prev,
      next,
    ) {
      _updateMarkerCacheForAllDefsThrottled();
      // When going online, ensure a visible selection exists for current defs
      if (next && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final currentSelectedId = ref.read(selectedDefinitionIdProvider);
          final defs = ref.read(filteredDefinitionsProvider);
          if (defs.isEmpty) return;
          final hasSelectedInDefs = currentSelectedId != null &&
              defs.any((d) => d.definitionId == currentSelectedId);
          if (!hasSelectedInDefs) {
            _selectDefinition(
              defs.first,
              0,
              fromUserInteraction: false,
              animateMap: true,
            );
          }
        });
      }
    });

    // After the initial online job load completes, ensure selection & highlight
    ref.listen<bool>(
      jobsNotifierProvider.select((s) => s.hasLoadedInitialJobs),
      (prev, next) {
        if (next && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            final defs = ref.read(filteredDefinitionsProvider);
            if (defs.isEmpty) return;
            final currentSelectedId = ref.read(selectedDefinitionIdProvider);
            final hasSelectedInDefs = currentSelectedId != null &&
                defs.any((d) => d.definitionId == currentSelectedId);
            if (!hasSelectedInDefs) {
              // Ensure markers/maps are up-to-date, then select first
              await _performFullMarkerUpdate();
              _selectDefinition(
                defs.first,
                0,
                fromUserInteraction: false,
                animateMap: true,
              );
            }
          });
        }
      },
    );

    final screenHeight = MediaQuery.of(context).size.height;
    final minSheetSize = _computeMinSheetSize(context);
    // Fallback guess until post-frame measurement runs
    // Set static max size as requested
    const maxSheetSize = 0.98;
    final sheetSnapSizes = [minSheetSize, 0.4, maxSheetSize];
    final isOnline = jobsState.isOnline;
    final isTest = PoofWorkerFlavorConfig.instance.testMode;
    final isLoadingOpenJobs = jobsState.isLoadingOpenJobs;

    // Cache sheet size bounds for fraction calculations
    _cachedMinSheetSize = minSheetSize;
    _cachedMaxSheetSize = maxSheetSize;

    // Removed automatic per-frame page syncing. With stable PageView keys,
    // the currently visible item remains stable across reorders. Page moves
    // now happen only in response to selection changes above.

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      drawer: const WorkerSideDrawer(),
      body: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (PointerDownEvent e) {
              _tapStartPosition = e.position;
              _tapPointerId = e.pointer;
              _tapStartTime = DateTime.now();
              _tapCancelled = false;
            },
            onPointerMove: (PointerMoveEvent e) {
              if (e.pointer != _tapPointerId ||
                  _tapCancelled ||
                  _tapStartPosition == null) {
                return;
              }

              final travelled = (e.position - _tapStartPosition!).distance;
              if (travelled > kTouchSlop) {
                _tapCancelled = true;
              }
            },
            onPointerUp: (PointerUpEvent e) {
              if (e.pointer != _tapPointerId ||
                  _tapCancelled ||
                  _tapStartTime == null) {
                return;
              }

              final held = DateTime.now().difference(_tapStartTime!);
              if (held <= _quickTapMax) {
                final RenderBox renderBox =
                    context.findRenderObject() as RenderBox;
                final globalPosition = renderBox.localToGlobal(e.position);
                ref.read(tapRippleProvider.notifier).add(globalPosition);
              }
            },
            onPointerCancel: (_) {
              _tapCancelled = true;
            },
            child: Stack(
              children: [
                VisibilityDetector(
                  key: const Key('home_map_visibility'),
                  onVisibilityChanged: (visibilityInfo) {
                    if (visibilityInfo.visibleFraction > 0.0 &&
                        _mapController != null) {
                      if (mounted) {
                        _mapController!.animateCamera(
                          CameraUpdate.newCameraPosition(
                            ref.read(currentMapCameraPositionProvider),
                          ),
                          duration: const Duration(milliseconds: 150),
                        );
                      }
                    }
                  },
                  child: MapPane(
                    key: const Key('map_pane'),
                    initialCameraPosition: liveCameraPosition,
                    mapStyle: _mapStyle,
                    locationPermissionOK: _locationPermissionOK,
                    onMapCreated: _onMapPaneCreated,
                    onCameraMove: _onCameraMove,
                    onCameraIdle: _onCameraIdle,
                    onCameraMoveStarted: _onCameraMoveStarted,
                    onTap: _onMapTap,
                  ),
                ),
                const TapRippleOverlay(),
              ],
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: GoOnlineButton(key: _goOnlineKey),
                  ),
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16, left: 16),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _scaffoldKey.currentState?.openDrawer(),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          key: _menuButtonKey,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).cardColor.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.10),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.menu,
                            size: 28,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_locationPermissionOK)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16, right: 16),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isSnappingToLocation
                              ? null
                              : _snapToUserLocation,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            key: _locButtonKey,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).cardColor.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.10),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: _isSnappingToLocation
                                ? const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Icon(
                                    Icons.my_location,
                                    size: 28,
                                    color: Colors.black87,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (carouselDefs.isNotEmpty)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: (screenHeight * minSheetSize) - 15,
                      ),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: _carouselOpacity,
                        child: JobDefinitionCarousel(
                          definitions: carouselDefs,
                          pageController: _carouselPageController,
                          onPageChanged: (idx) {
                            if (_ignoreNextPageChange) {
                              _ignoreNextPageChange = false;
                              return;
                            }
                            if (idx < carouselDefs.length) {
                              _selectDefinition(
                                carouselDefs[idx],
                                idx,
                                fromUserInteraction: true,
                                animateMap: true,
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                JobsSheet(
                  appLocalizations: appLocalizations,
                  sheetController: _sheetController,
                  minChildSize: minSheetSize,
                  maxChildSize: maxSheetSize,
                  snapSizes: sheetSnapSizes,
                  screenHeight: screenHeight,
                  allDefinitions: filteredDefs,
                  isOnline: isOnline,
                  isTestMode: isTest,
                  isLoadingJobs: isLoadingOpenJobs,
                  hasLoadedInitialJobs: ref
                      .watch(jobsNotifierProvider)
                      .hasLoadedInitialJobs,
                  sortBy: ref.watch(jobsSortByProvider),
                  onSortChanged: (val) {
                    if (mounted) {
                      ref.read(jobsSortByProvider.notifier).state = val;
                      _restoreSelection();
                    }
                  },
                  showSearchBar: _isSearchVisible,
                  toggleSearchBar: () {
                    final willBeVisible = !_isSearchVisible;

                    setState(() {
                      _isSearchVisible = willBeVisible;
                    });

                    if (willBeVisible) {
                      // Opening search bar
                      _searchFocusNode.requestFocus();
                      if (_sheetFraction() < maxSheetSize) {
                        setState(() => _isAnimatingSheet = true);
                        _sheetController
                            .animateTo(
                              maxSheetSize,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                            )
                            .whenComplete(() {
                              if (mounted) {
                                setState(() => _isAnimatingSheet = false);
                              }
                            });
                      }
                    } else {
                      // Closing search bar
                      _searchController.clear();
                      ref.read(jobsSearchQueryProvider.notifier).state = '';
                      _searchFocusNode.unfocus();
                    }
                  },
                  searchQuery: ref.watch(jobsSearchQueryProvider),
                  onSearchChanged: (val) {
                    if (mounted) {
                      ref.read(jobsSearchQueryProvider.notifier).state = val;
                    }
                  },
                  searchController: _searchController,
                  searchFocusNode: _searchFocusNode,
                  onViewOnMapPressed: _handleViewOnMapFromSheet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
///  M A P   P A N E (Isolated GoogleMap Widget - Simpler)
/// ─────────────────────────────────────────────────────────────────────────
class MapPane extends ConsumerWidget {
  final CameraPosition initialCameraPosition;
  final String mapStyle;
  final bool locationPermissionOK;
  final Function(GoogleMapController) onMapCreated;
  final Function(CameraPosition) onCameraMove;
  final Function() onCameraIdle;
  final Function() onCameraMoveStarted;
  final Future<void> Function(LatLng)? onTap;

  const MapPane({
    super.key,
    required this.initialCameraPosition,
    required this.mapStyle,
    required this.locationPermissionOK,
    required this.onMapCreated,
    required this.onCameraMove,
    required this.onCameraIdle,
    required this.onCameraMoveStarted,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markers = ref.watch(visibleMarkersProvider);

    return GoogleMap(
      style: mapStyle.isEmpty ? null : mapStyle,
      onMapCreated: onMapCreated,
      onCameraMove: onCameraMove,
      onCameraIdle: onCameraIdle,
      onCameraMoveStarted: onCameraMoveStarted,
      onTap: onTap,
      markers: markers,
      myLocationEnabled: locationPermissionOK,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      initialCameraPosition: initialCameraPosition,
    );
  }
}

/// Returns true if the open jobs list changed in a way that warrants
/// recentering the UI selection. Currently this happens only when the list
/// shrinks, indicating jobs were removed.
bool shouldRecenterOnOpenJobsChange(
  List<JobInstance>? previous,
  List<JobInstance> current,
) {
  if (previous == null) return true;
  return current.length < previous.length;
}
