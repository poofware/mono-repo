import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/features/jobs/providers/providers.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/tap_ripple_overlay.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:poof_worker/core/providers/initial_setup_providers.dart';

class JobMapPage extends ConsumerStatefulWidget {
  final JobInstance job;
  final VoidCallback? onReady;
  final bool isForWarmup;
  final bool buildAsScaffold;
  final Function(GoogleMapController)? onMapCreated;
  final VoidCallback? onCameraMoveStarted;

  const JobMapPage({
    super.key,
    required this.job,
    this.onReady,
    this.isForWarmup = false,
    this.buildAsScaffold = true,
    this.onMapCreated,
    this.onCameraMoveStarted,
  });

  static final _warmedJobIds = <String>{};

  /// Clears the warmed flag for a specific job instance.
  ///
  /// This is used by the cache eviction logic so that subsequent warm-ups
  /// can complete promptly (i.e., invoke onReady) instead of waiting for
  /// a safety timeout due to an already-warmed short-circuit.
  static void clearWarmed(String instanceId) {
    _warmedJobIds.remove(instanceId);
  }

  @override
  ConsumerState<JobMapPage> createState() => _JobMapPageState();
}

class _JobMapPageState extends ConsumerState<JobMapPage>
    with AutomaticKeepAliveClientMixin {
  final Completer<GoogleMapController> _internalMapController = Completer();
  Set<Marker> _markers = {};
  bool _isMapReady = false;
  String _mapStyle = '';
  CameraPosition? _savedCameraPosition;

  static const _quickTapMax = Duration(milliseconds: 180);
  Offset? _tapStartPosition;
  int? _tapPointerId;
  DateTime? _tapStartTime;
  bool _tapCancelled = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // This now correctly sets the initial state if the map was already warmed.
    _isMapReady = JobMapPage._warmedJobIds.contains(widget.job.instanceId);
    _createMarkers();
    // Prefer preloaded style (from app boot) to avoid disk IO during map init.
    final preloadedStyle = ref.read(mapStyleJsonProvider);
    if (preloadedStyle != null) {
      _mapStyle = preloadedStyle;
    } else {
      rootBundle.loadString('assets/jsons/map_style.json').then((style) {
        if (mounted) {
          setState(() => _mapStyle = style);
        }
      });
    }
  }

  void _createMarkers() {
    final Set<Marker> markers = {};
    for (final building in widget.job.buildings) {
      final markerId = MarkerId('building_${building.buildingId}');
      markers.add(
        Marker(
          markerId: markerId,
          position: LatLng(building.latitude, building.longitude),
          infoWindow: InfoWindow(title: building.name),
          consumeTapEvents: true,
          onTap: () {
            _internalMapController.future.then(
              (c) => c.showMarkerInfoWindow(markerId),
            );
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueViolet,
          ),
          zIndexInt: 0,
        ),
      );
    }
    for (final dumpster in widget.job.dumpsters) {
      final markerId = MarkerId('dumpster_${dumpster.dumpsterId}');
      markers.add(
        Marker(
          markerId: markerId,
          position: LatLng(dumpster.latitude, dumpster.longitude),
          infoWindow: InfoWindow(title: 'Dumpster ${dumpster.number}'),
          consumeTapEvents: true,
          onTap: () {
            _internalMapController.future.then(
              (c) => c.showMarkerInfoWindow(markerId),
            );
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          zIndexInt: 1,
        ),
      );
    }
    setState(() => _markers = markers);
  }

  LatLngBounds _calculateBounds() {
    // This logic is unchanged
    if (_markers.isEmpty) {
      return LatLngBounds(
        southwest: LatLng(
          widget.job.property.latitude,
          widget.job.property.longitude,
        ),
        northeast: LatLng(
          widget.job.property.latitude,
          widget.job.property.longitude,
        ),
      );
    }
    double minLat = _markers.first.position.latitude;
    double maxLat = _markers.first.position.latitude;
    double minLng = _markers.first.position.longitude;
    double maxLng = _markers.first.position.longitude;
    for (final marker in _markers) {
      if (marker.position.latitude < minLat) {
        minLat = marker.position.latitude;
      }
      if (marker.position.latitude > maxLat) {
        maxLat = marker.position.latitude;
      }
      if (marker.position.longitude < minLng) {
        minLng = marker.position.longitude;
      }
      if (marker.position.longitude > maxLng) {
        maxLng = marker.position.longitude;
      }
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _waitUntilTilesRender(GoogleMapController controller) async {
    // On iOS, avoid expensive snapshot polling during warm-up to reduce latency.
    if (Platform.isIOS) {
      return;
    }
    // Strengthen tile readiness for flaky Android devices
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(deadline)) {
      final bytes = await controller.takeSnapshot();
      if (bytes != null && bytes.isNotEmpty) {
        debugPrint(
          "JobMapPage: Tiles rendered successfully via snapshot poll.",
        );
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    debugPrint("JobMapPage: Snapshot polling timed‑out; proceeding anyway.");
  }

  void _onMapCreated(GoogleMapController controller) {
    if (!_internalMapController.isCompleted) {
      _internalMapController.complete(controller);
    }
    widget.onMapCreated?.call(controller);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final bool isAlreadyWarmed =
          JobMapPage._warmedJobIds.contains(widget.job.instanceId);
      try {
        final GoogleMapController mapController =
            await _internalMapController.future;
        if (_savedCameraPosition != null) {
          await mapController.moveCamera(
            CameraUpdate.newCameraPosition(_savedCameraPosition!),
          );
          return;
        }

        if (_markers.isNotEmpty && (!isAlreadyWarmed || widget.isForWarmup)) {
          final bounds = _calculateBounds();

          try {
            if (widget.isForWarmup) {
              await mapController.moveCamera(
                CameraUpdate.newLatLngBounds(bounds, 60.0),
              );
              await _waitUntilTilesRender(mapController);
            } else {
              await mapController.animateCamera(
                CameraUpdate.newLatLngBounds(bounds, 60.0),
              );
              await Future.delayed(const Duration(milliseconds: 250));
            }
          } catch (e, s) {
            debugPrint('JobMapPage: camera update failed: $e\n$s');
          }

          try {
            final zoom = await mapController.getZoomLevel();
            final center = LatLng(
              (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
              (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
            );
            _savedCameraPosition = CameraPosition(target: center, zoom: zoom);
          } catch (e, s) {
            debugPrint('JobMapPage: read zoom failed: $e\n$s');
          }
        }
      } catch (e, s) {
        debugPrint('JobMapPage: onMapCreated post-frame error: $e\n$s');
      } finally {
        if (mounted && !isAlreadyWarmed) {
          setState(() => _isMapReady = true);
          JobMapPage._warmedJobIds.add(widget.job.instanceId);
          widget.onReady?.call();
        }
      }
    });
  }

  Widget _buildMapContent() {
    final initialCameraPosition = _savedCameraPosition ??
        CameraPosition(
          target: LatLng(
            widget.job.property.latitude,
            widget.job.property.longitude,
          ),
          zoom: 16,
        );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _tapStartPosition = e.position;
        _tapPointerId = e.pointer;
        _tapStartTime = DateTime.now();
        _tapCancelled = false;
      },
      onPointerMove: (e) {
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
      onPointerUp: (e) {
        if (e.pointer != _tapPointerId ||
            _tapCancelled ||
            _tapStartTime == null) {
          return;
        }
        final held = DateTime.now().difference(_tapStartTime!);
        if (held <= _quickTapMax) {
          final RenderBox renderBox = context.findRenderObject() as RenderBox;
          final globalPosition = renderBox.localToGlobal(e.position);
          ref.read(tapRippleProvider.notifier).add(globalPosition);
        }
      },
      onPointerCancel: (_) => _tapCancelled = true,
      child: Stack(
        children: [
          Builder(
            builder: (context) {
              final map = GoogleMap(
                mapType: MapType.satellite,
                style: _mapStyle.isEmpty ? null : _mapStyle,
                initialCameraPosition: initialCameraPosition,
                onMapCreated: _onMapCreated,
                onCameraMoveStarted: widget.onCameraMoveStarted,
                onCameraMove: (position) => _savedCameraPosition = position,
                markers: _markers,
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                zoomControlsEnabled: false,
                padding: const EdgeInsets.only(top: 0),
              );
              return map;
            },
          ),
          const TapRippleOverlay(),
          // This AnimatedOpacity now works correctly because _isMapReady
          // will be true from the very first frame on the new page.
          AnimatedOpacity(
            opacity: _isMapReady ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            alwaysIncludeSemantics: false,
            child: _isMapReady
                ? const SizedBox.shrink()
                : Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // This logic is unchanged
    final mapContent = _buildMapContent();
    if (widget.buildAsScaffold) {
      return Scaffold(
        body: Stack(
          children: [
            mapContent,
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: FloatingActionButton(
                    mini: true,
                    onPressed: () => Navigator.of(context).pop(),
                    backgroundColor: Colors.white.withAlpha(230),
                    elevation: 2,
                    child: const Icon(Icons.arrow_back, color: Colors.black87),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      return mapContent;
    }
  }
}
