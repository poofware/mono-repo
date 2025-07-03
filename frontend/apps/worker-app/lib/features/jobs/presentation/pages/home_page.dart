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
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations

import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/utils/location_permissions.dart';
import 'package:poof_worker/features/account/presentation/pages/worker_drawer_page.dart';
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

/// ─────────────────────────────────────────────────────────────────────────
///  P R O V I D E R S (Jobs List Related)
/// ─────────────────────────────────────────────────────────────────────────

final jobsSortByProvider = StateProvider<String>((_) => 'distance');
final jobsSearchQueryProvider = StateProvider<String>((_) => '');

final filteredDefinitionsProvider = Provider<List<DefinitionGroup>>((ref) {
  final jobsState = ref.watch(jobsNotifierProvider);
  final sortBy = ref.watch(jobsSortByProvider);
  final query = ref.watch(jobsSearchQueryProvider).trim().toLowerCase();

  final list = groupOpenJobs(jobsState.openJobs).where((d) {
    return d.propertyName.toLowerCase().contains(query) ||
        d.propertyAddress.toLowerCase().contains(query);
  }).toList();

  switch (sortBy) {
    case 'pay':
      list.sort((a, b) => b.pay.compareTo(a.pay));
      break;
    default:
      list.sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
  }
  return list;
});

/// ─────────────────────────────────────────────────────────────────────────
///  H O M E  P A G E  C O N S T A N T S
/// ─────────────────────────────────────────────────────────────────────────

const kDefaultMapZoom = 14.5;
const kLosAngelesLatLng = LatLng(34.0522, -118.2437);
const kGenericFallbackLatLng = LatLng(0.0, 0.0);
const kGenericFallbackZoom = 2.0;

Duration _cameraPanDuration = const Duration(
    milliseconds: 350); // Used for UI animations like sheet & carousel

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
  final _sheetController = DraggableScrollableController();
  late final PageController _carouselPageController =
      PageController(viewportFraction: 0.9); // UPDATED viewportFraction
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  GoogleMapController? _mapController;
  CameraPosition? _lastCameraMove; // Last position reported by onCameraMove

  String _mapStyle = '';
  bool _locationPermissionOK = false;
  double _carouselOpacity = 1.0;
  bool _ignoreNextPageChange = false;
  bool _isSnappingToLocation = false;

  List<JobInstance>? _previousOpenJobsIdentity;
  bool _isInitialLoad = true;

  static const double _minSheetSize = 0.15;
  static const double _maxSheetSize = 0.85;
  static const List<double> _sheetSnapSizes = [
    _minSheetSize,
    0.4,
    _maxSheetSize
  ];

  // For marker tap communication from isolate
  final ReceivePort _markerTapReceivePort = ReceivePort();
  // Timer for throttling marker updates
  Timer? _markerUpdateThrottleTimer;

  // ---- Tap-vs-Drag/Hold helpers for ripple effect ----
  static const _quickTapMax = Duration(milliseconds: 180);
  Offset? _tapStartPosition;
  int? _tapPointerId;
  DateTime? _tapStartTime;
  bool _tapCancelled = false;
  // ----------------------------------------------------

  List<DefinitionGroup> _defs() => ref.read(filteredDefinitionsProvider);
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
                  target: kLosAngelesLatLng, zoom: kDefaultMapZoom);
      _lastCameraMove = ref.read(currentMapCameraPositionProvider);
      _initializePage();
    });

    _sheetController.addListener(_onSheetSizeChanged);

    if (IsolateNameServer.lookupPortByName(kMarkerTapPortName) == null) {
      IsolateNameServer.registerPortWithName(
          _markerTapReceivePort.sendPort, kMarkerTapPortName);
    }
    _markerTapReceivePort.listen(_handleMarkerTapFromIsolate);
    
    rootBundle.loadString('assets/jsons/map_style.json').then((style) {
      if (mounted) {
        setState(() => _mapStyle = style);
      }
    });
  }

  CameraPosition _currentLiveCameraPos() =>
      ref.read(currentMapCameraPositionProvider);

  /// Handles marker tap events sent from the isolate.
  void _handleMarkerTapFromIsolate(dynamic message) {
    if (message is String) {
      final definitionId = message;
      final currentFilteredDefs = ref.read(filteredDefinitionsProvider);
      final targetDef = currentFilteredDefs
          .firstWhereOrNull((d) => d.definitionId == definitionId);

      if (targetDef != null) {
        final idx = currentFilteredDefs.indexOf(targetDef);
        if (idx != -1) {
          _selectDefinition(targetDef, idx,
              fromUserInteraction: true, animateMap: false);
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
      final Map<String, Marker> newMarkerMap =
          await compute(rebuildAndCreateMarkersIsolate, args);
      if (mounted) {
        ref
            .read(jobMarkerCacheProvider.notifier)
            .replaceAllMarkers(newMarkerMap);
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
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 7),
          ),
        );
        if (!mounted) return;
        camToSet = CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: kDefaultMapZoom,
        );
      } catch (_) {
        if (!mounted) return;
        camToSet = storedPersistedCam ??
            const CameraPosition(
                target: kGenericFallbackLatLng, zoom: kGenericFallbackZoom);
      }
    } else {
      if (!mounted) return;
      camToSet = const CameraPosition(
          target: kLosAngelesLatLng, zoom: kDefaultMapZoom);
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

  void _moveOrAnimateMapToPosition(CameraPosition newPosition,
      {required bool animate}) {
    if (!mounted) return;

    final currentLivePos = _currentLiveCameraPos();
    if (currentLivePos != newPosition) {
      ref.read(currentMapCameraPositionProvider.notifier).state = newPosition;
    }
    ref.read(lastMapCameraPositionProvider.notifier).state = newPosition;
    _lastCameraMove = newPosition;

    if (_mapController == null) return;

    if (animate) {
      _mapController!.animateCamera(CameraUpdate.newCameraPosition(newPosition),
          duration: const Duration(milliseconds: 150));
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

  Future<void> _snapToUserLocation() async {
    if (!_locationPermissionOK || _isSnappingToLocation) return;
    if (!mounted) return;
    setState(() => _isSnappingToLocation = true);

    // Capture context before async gap
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final BuildContext capturedContext = context;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 7),
        ),
      );
      if (!mounted) return;
      final userLatLng = LatLng(pos.latitude, pos.longitude);
      final zoom = _mapController != null
          ? await _mapController!.getZoomLevel()
          : kDefaultMapZoom;
      if (!mounted) return;
      final cam = CameraPosition(target: userLatLng, zoom: zoom);
      _moveOrAnimateMapToPosition(cam, animate: true);
    } catch (e) {
      if (!capturedContext.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(capturedContext)
                .homePageCouldNotGetLocation(e.toString()))),
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
      target = defs.firstWhere((d) => d.definitionId == persistedId,
          orElse: () => defs.first);
    } else {
      target = defs.first;
    }

    final idx = defs.indexOf(target);
    if (idx != -1) {
      _selectDefinition(target, idx,
          fromUserInteraction: false, animateMap: true);
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
        LatLng targetPosition = LatLng(
          def.instances.first.property.latitude,
          def.instances.first.property.longitude,
        );
        if (def.instances.first.buildings.isNotEmpty &&
            def.instances.first.buildings.first.latitude != 0 &&
            def.instances.first.buildings.first.longitude != 0) {
          final building = def.instances.first.buildings.first;
          targetPosition = LatLng(building.latitude, building.longitude);
        }
        final targetCameraPos = CameraPosition(
          target: targetPosition,
          zoom: _currentLiveCameraPos().zoom,
        );
        _moveOrAnimateMapToPosition(targetCameraPos, animate: true);
      }
    }
  }

  void _syncCarouselPage(List<DefinitionGroup> defs) {
    if (!mounted) return;
    final selectedId = _selectedDefId();
    if (selectedId == null ||
        !_carouselPageController.hasClients ||
        defs.isEmpty) {
      return;
    }
    final idx = defs.indexWhere((d) => d.definitionId == selectedId);
    if (idx != -1 && _carouselPageController.page?.round() != idx) {
      _ignoreNextPageChange = true;
      _carouselPageController.jumpToPage(idx);
    }
  }

  void _onSheetSizeChanged() {
    if (!mounted) return;
    final opacity = _sheetController.size <= 0.3 ? 1.0 : 0.0;
    if (_carouselOpacity != opacity) setState(() => _carouselOpacity = opacity);
  }

  void _onMapPaneCreated(GoogleMapController controller) {
    _mapController = controller;
    if (mounted) {
      final liveCamPos = _currentLiveCameraPos();
      _mapController!.moveCamera(
        CameraUpdate.newCameraPosition(liveCamPos),
      );
      _restoreSelection();
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

  void _handleViewOnMapFromSheet(DefinitionGroup definition) {
    if (!mounted) return;
    _sheetController.animateTo(
      _minSheetSize,
      duration: _cameraPanDuration,
      curve: Curves.easeOutCubic,
    );
    final idx = _defs().indexOf(definition);
    _selectDefinition(definition, idx,
        fromUserInteraction: true, animateMap: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // --- Post-Boot Error Listener ---
    ref.listen<List<Object>>(postBootErrorProvider, (previous, next) {
      if (next.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final scaffoldMessenger = ScaffoldMessenger.of(context);
            for (final error in next) {
              final message = userFacingMessageFromObject(context, error);
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text(message),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
            ref.read(postBootErrorProvider.notifier).state = [];
          }
        });
      }
    });

    ref.listen<List<DefinitionGroup>>(filteredDefinitionsProvider,
        (previous, next) {
      _updateMarkerCacheForAllDefsThrottled();
    });

    ref.listen<String?>(selectedDefinitionIdProvider,
        (previousSelectedId, newSelectedId) {
      ref
          .read(jobMarkerCacheProvider.notifier)
          .updateSelection(newSelectedId, previousSelectedId);
    });

    final jobsState = ref.watch(jobsNotifierProvider);
    final newOpenJobs = jobsState.openJobs;
    final filteredDefs = ref.watch(filteredDefinitionsProvider);
    final liveCameraPosition = ref.watch(currentMapCameraPositionProvider);
    final appLocalizations = AppLocalizations.of(context);

    final bool openJobsListActuallyChanged =
        _previousOpenJobsIdentity != null &&
            !identical(_previousOpenJobsIdentity, newOpenJobs);
    final bool isFirstTimeLoadingJobs =
        _isInitialLoad && newOpenJobs.isNotEmpty;

    if ((openJobsListActuallyChanged || isFirstTimeLoadingJobs) &&
        newOpenJobs.isNotEmpty) {
      final currentFilteredDefsForRecenter =
          ref.read(filteredDefinitionsProvider);
      if (currentFilteredDefsForRecenter.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _selectDefinition(
              currentFilteredDefsForRecenter.first,
              0,
              fromUserInteraction: false,
              animateMap: true,
            );
            if (_isInitialLoad) {
              _isInitialLoad = false;
            }
          }
        });
      }
    }
    _previousOpenJobsIdentity = newOpenJobs;

    ref.listen<List<DefinitionGroup>>(filteredDefinitionsProvider,
        (previousFiltered, nextFiltered) {
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

    ref.listen<bool>(jobsNotifierProvider.select((s) => s.isOnline),
        (prev, next) {
      _updateMarkerCacheForAllDefsThrottled();
    });

    final screenHeight = MediaQuery.of(context).size.height;
    final isOnline = jobsState.isOnline;
    final isTest = PoofWorkerFlavorConfig.instance.testMode;
    final isLoadingOpenJobs = jobsState.isLoadingOpenJobs;

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
          if (mounted) _syncCarouselPage(filteredDefs);
        });

    return Scaffold(
      key: _scaffoldKey,
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
                  _tapStartPosition == null) return;

              final travelled = (e.position - _tapStartPosition!).distance;
              if (travelled >
                  kTouchSlop) {
                _tapCancelled = true;
              }
            },
            onPointerUp: (PointerUpEvent e) {
              if (e.pointer != _tapPointerId ||
                  _tapCancelled ||
                  _tapStartTime == null) return;

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
                              ref.read(currentMapCameraPositionProvider)),
                          duration: const Duration(milliseconds: 150),
                        );
                      }
                    }
                  },
                  child: MapPane(
                    key: const Key('map_pane'),
                    initialCameraPosition: liveCameraPosition,
                    mapStyle: _mapStyle,
                    locationPermissionOK:
                        _locationPermissionOK, 
                    onMapCreated: _onMapPaneCreated,
                    onCameraMove: _onCameraMove,
                    onCameraIdle: _onCameraIdle,
                    onCameraMoveStarted: _onCameraMoveStarted,
                  ),
                ),
                const TapRippleOverlay(),
              ],
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Center(child: GoOnlineButton()),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .cardColor
                              .withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.menu,
                            size: 28, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
                if (_locationPermissionOK)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap:
                            _isSnappingToLocation ? null : _snapToUserLocation,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .cardColor
                                .withValues(alpha: 0.85),
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
                                      strokeWidth: 2.5),
                                )
                              : const Icon(Icons.my_location,
                                  size: 28, color: Colors.black87),
                        ),
                      ),
                    ),
                  ),
                if (filteredDefs.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: screenHeight * _minSheetSize - 10,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: _carouselOpacity,
                      child: JobDefinitionCarousel(
                        definitions: filteredDefs,
                        pageController: _carouselPageController,
                        onPageChanged: (idx) {
                          if (_ignoreNextPageChange) {
                            _ignoreNextPageChange = false;
                            return;
                          }
                          if (idx < filteredDefs.length) {
                            _selectDefinition(filteredDefs[idx], idx,
                                fromUserInteraction: true, animateMap: true);
                          }
                        },
                      ),
                    ),
                  ),
                JobsSheet(
                  appLocalizations: appLocalizations,
                  sheetController: _sheetController,
                  minChildSize: _minSheetSize,
                  maxChildSize: _maxSheetSize,
                  snapSizes: _sheetSnapSizes,
                  screenHeight: screenHeight,
                  allDefinitions: filteredDefs,
                  isOnline: isOnline,
                  isTestMode: isTest,
                  isLoadingJobs: isLoadingOpenJobs,
                  sortBy: ref.watch(jobsSortByProvider),
                  onSortChanged: (val) {
                    if (mounted) {
                      ref.read(jobsSortByProvider.notifier).state = val;
                      _restoreSelection();
                    }
                  },
                  showSearchBar: ref.watch(jobsSearchQueryProvider).isNotEmpty,
                  toggleSearchBar: () {
                    if (mounted) {
                      final nowSearchQuery =
                          ref.read(jobsSearchQueryProvider);
                      if (nowSearchQuery.isNotEmpty) {
                        _searchController.clear();
                        ref.read(jobsSearchQueryProvider.notifier).state = '';
                        _searchFocusNode.unfocus();
                      } else {
                        _searchFocusNode.requestFocus();
                      }
                      _restoreSelection();
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

  const MapPane({
    super.key,
    required this.initialCameraPosition,
    required this.mapStyle,
    required this.locationPermissionOK,
    required this.onMapCreated,
    required this.onCameraMove,
    required this.onCameraIdle,
    required this.onCameraMoveStarted,
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
      markers: markers,
      myLocationEnabled:
          locationPermissionOK, 
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
      initialCameraPosition: initialCameraPosition,
    );
  }
}
