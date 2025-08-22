// worker-app/lib/features/jobs/presentation/widgets/accepted_job_details_sheet.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/core/utils/location_permissions.dart';
import 'package:geolocator/geolocator.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
// job_map_page is referenced by JobMapCache; no direct use here.
import 'job_map_cache.dart';
import 'view_job_map_button.dart';
import 'package:poof_worker/features/jobs/presentation/pages/job_in_progress_page.dart'; // Import the page
import 'info_widgets.dart';
import 'package:poof_worker/core/presentation/widgets/app_top_snackbar.dart';

class AcceptedJobDetailsSheet extends ConsumerStatefulWidget {
  final JobInstance job;

  const AcceptedJobDetailsSheet({super.key, required this.job});

  // (shared map caching utilities are provided by JobMapCache)

  @override
  ConsumerState<AcceptedJobDetailsSheet> createState() =>
      _AcceptedJobDetailsSheetState();
}

class _AcceptedJobDetailsSheetState
    extends ConsumerState<AcceptedJobDetailsSheet> with TickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isUnaccepting = false;
  bool _isStartingJob = false;

  /// A getter to simplify checking if any async operation is in progress.
  bool get _isProcessing => _isStartingJob || _isUnaccepting;

  // Drag/scroll sync state (mirrors JobAcceptSheet)
  final GlobalKey _sheetBoundaryKey = GlobalKey();
  final ScrollController _bodyScrollController = ScrollController();
  bool _isDismissing = false;
  double _pullDownAccumulated = 0.0;
  static const double _dismissFlingVelocity = 340.0;
  static const double _microDismissOffsetPx = 12.0;
  static const double _microDismissVelocity = 260.0;
  double _dragOffset = 0.0;
  late final AnimationController _dragResetController;
  Animation<double>? _dragResetAnimation;
  bool _isPointerDown = false;
  bool _isDraggingSheetViaPointer = false;
  bool _gestureBeganAtTop = false;
  bool _lastGestureBeganAtTop = false;
  int? _activePointerId;
  double? _lastPointerY;
  double? _lastPointerX;
  Axis? _lockedPointerAxis;
  int? _lastPointerSampleMs;
  double _lastPointerVelocityY = 0.0;
  bool _didRequestRoutePop = false;
  ui.Image? _snapshotImage;
  OverlayEntry? _dismissOverlayEntry;
  AnimationController? _dismissOverlayController;

  @override
  void initState() {
    super.initState();
    JobMapCache.cancelEvict(widget.job.instanceId);
    _dragResetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )
      ..addListener(() {
        if (!mounted) return;
        final value = _dragResetAnimation?.value ?? 0.0;
        setState(() => _dragOffset = value);
      })
      ..addStatusListener((status) {
        if (!mounted) return;
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          if (_dragOffset != 0.0) setState(() => _dragOffset = 0.0);
        }
      });
  }

  @override
  void dispose() {
    JobMapCache.scheduleEvict(widget.job.instanceId);
    _bodyScrollController.dispose();
    try { _dismissOverlayController?.dispose(); } catch (_) {}
    try { _dismissOverlayEntry?.remove(); } catch (_) {}
    _dragResetController.dispose();
    super.dispose();
  }

  double _dismissDistancePx(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = screenHeight * 0.95;
    final raw = maxSheetHeight * 0.10;
    if (raw < 36.0) return 36.0;
    if (raw > 84.0) return 84.0;
    return raw;
  }

  void _animateDragOffsetToZero() {
    if (_dragOffset == 0.0) return;
    _dragResetAnimation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
      CurvedAnimation(parent: _dragResetController, curve: Curves.easeOutCubic),
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _dragResetController
        ..stop()
        ..value = 0.0
        ..forward();
    });
  }

  void _requestPopOnce() {
    if (_didRequestRoutePop) return;
    _didRequestRoutePop = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).maybePop();
    });
  }

  Future<void> _dismissWithOverlay(double releaseVelocityY) async {
    final boundaryContext = _sheetBoundaryKey.currentContext;
    if (boundaryContext == null) {
      _requestPopOnce();
      return;
    }
    
    final boundary = boundaryContext.findRenderObject() as RenderRepaintBoundary?;
    if (boundary != null) {
      try {
        final dpr = MediaQuery.of(boundaryContext).devicePixelRatio;
        _snapshotImage = await boundary.toImage(pixelRatio: dpr);
      } catch (_) {}
    }

    if (_snapshotImage == null) {
      _requestPopOnce();
      return;
    }

    if (!mounted) return;
    
    _dismissOverlayController?.dispose();
    _dismissOverlayController = AnimationController(vsync: this);
    final screenHeight = MediaQuery.of(context).size.height;
    final double v = releaseVelocityY.isFinite ? releaseVelocityY.abs() : 0.0;
    final double effectiveV = v > 0.0 ? v : _dismissFlingVelocity;
    double durationMs = (screenHeight / (effectiveV + 300.0)) * 1000.0;
    durationMs = durationMs.clamp(160.0, 280.0);
    _dismissOverlayController!.duration = Duration(milliseconds: durationMs.round());

    final animation = CurvedAnimation(
      parent: _dismissOverlayController!,
      curve: Curves.linearToEaseOut,
    );

    _dismissOverlayEntry?.remove();
    _dismissOverlayEntry = OverlayEntry(
      builder: (_) => IgnorePointer(
        ignoring: true,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final dy = animation.value * (screenHeight + 60.0);
            return Align(
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                offset: Offset(0, dy),
                child: RawImage(image: _snapshotImage),
              ),
            );
          },
        ),
      ),
    );
    if (mounted) {
      final overlay = Overlay.of(context, rootOverlay: true);
      overlay.insert(_dismissOverlayEntry!);
    }
    _requestPopOnce();
    try { await _dismissOverlayController!.forward(); } catch (_) {}
    try { _dismissOverlayEntry?.remove(); _dismissOverlayEntry = null; } catch (_) {}
  }

  void _animateDismissWithVelocityAndPop(double releaseVelocityY) {
    if (_isDismissing) return;
    _isDismissing = true;
    _dismissWithOverlay(releaseVelocityY);
  }

  void _handlePointerUpOrCancel() {
    final bool isAtTop = !_bodyScrollController.hasClients ||
        _bodyScrollController.position.pixels <= 0;
    final bool shouldDismissByVelocity = isAtTop && _gestureBeganAtTop &&
        _lockedPointerAxis != Axis.horizontal &&
        _lastPointerVelocityY >= _dismissFlingVelocity;
    final bool shouldDismissByMicroFlick = isAtTop && _gestureBeganAtTop &&
        _lockedPointerAxis != Axis.horizontal &&
        (_dragOffset >= _microDismissOffsetPx ||
            _pullDownAccumulated >= _microDismissOffsetPx) &&
        _lastPointerVelocityY >= _microDismissVelocity;
    if (_dragOffset > 0.0 || shouldDismissByVelocity || shouldDismissByMicroFlick) {
      final bool shouldDismissByOffset = _dragOffset >= _dismissDistancePx(context);
      if (shouldDismissByVelocity || shouldDismissByOffset || shouldDismissByMicroFlick) {
        _animateDismissWithVelocityAndPop(_lastPointerVelocityY);
      } else {
        _animateDragOffsetToZero();
      }
    }
    _pullDownAccumulated = 0.0;
    _isPointerDown = false;
    _isDraggingSheetViaPointer = false;
    _lastGestureBeganAtTop = _gestureBeganAtTop;
    _gestureBeganAtTop = false;
    _activePointerId = null;
    _lastPointerY = null;
    _lastPointerX = null;
    _lockedPointerAxis = null;
    _lastPointerSampleMs = null;
    _lastPointerVelocityY = 0.0;
  }

  bool _handleBodyScrollNotification(ScrollNotification notification) {
    // Mirror JobAcceptSheet’s behavior
    final dir = notification.metrics.axisDirection;
    if (dir == AxisDirection.left || dir == AxisDirection.right) return false;
    if (_isPointerDown) return false;

    if (notification is ScrollStartNotification) {
      if (_dragResetController.isAnimating) _dragResetController.stop();
    }
    final bool isAtTop = !_bodyScrollController.hasClients ||
        _bodyScrollController.position.pixels <= 0;

    if (notification is OverscrollNotification) {
      if (_lastGestureBeganAtTop && isAtTop && notification.overscroll < 0) {
        final delta = -notification.overscroll;
        if (_dragResetController.isAnimating) _dragResetController.stop();
        setState(() { _dragOffset = math.max(0.0, _dragOffset + delta); });
        _pullDownAccumulated += delta;
        return false;
      }
    }
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (isAtTop && delta != null) {
        if (_lastGestureBeganAtTop && delta < 0) {
          final d = -delta;
          if (_dragResetController.isAnimating) _dragResetController.stop();
          setState(() { _dragOffset = math.max(0.0, _dragOffset + d); });
          _pullDownAccumulated += d;
        } else if (_lastGestureBeganAtTop && delta > 0 && _dragOffset > 0) {
          if (_bodyScrollController.hasClients &&
              _bodyScrollController.position.pixels != 0.0) {
            _bodyScrollController.jumpTo(0.0);
          }
          setState(() { _dragOffset = math.max(0.0, _dragOffset - delta); });
        }
        return false;
      } else if (!isAtTop && _dragOffset != 0.0) {
        setState(() => _dragOffset = 0.0);
      }
    }
    if (notification is ScrollEndNotification) {
      final double velocityY =
          notification.dragDetails?.velocity.pixelsPerSecond.dy ?? 0.0;
      final threshold = _dismissDistancePx(context);
      final bool passedDistance = _pullDownAccumulated >= threshold;
      final bool passedVelocity = velocityY >= _dismissFlingVelocity;
      final bool distanceByOffset = _dragOffset >= threshold;
      if (_lastGestureBeganAtTop && isAtTop &&
          (passedVelocity || passedDistance || distanceByOffset)) {
        _animateDismissWithVelocityAndPop(velocityY);
      } else if (!_isPointerDown) {
        _animateDragOffsetToZero();
      }
      _pullDownAccumulated = 0.0;
      _lastGestureBeganAtTop = false;
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      final double? delta = notification.scrollDelta;
      if (delta != null && delta > 0) _pullDownAccumulated = 0.0;
    }
    return false;
  }

  // Deprecated local warm/show map handlers removed in favor of shared ViewJobMapButton

  DateTime? _parseJobServiceWindowEnd(JobInstance job) {
    try {
      final dateParts = job.serviceDate.split('-');
      // Use the service window end time
      final timeParts = job.workerServiceWindowEnd.split(':');
      if (dateParts.length != 3 || timeParts.length != 2) return null;

      final year = int.parse(dateParts[0]);
      final month = int.parse(dateParts[1]);
      final day = int.parse(dateParts[2]);

      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      // Log error or handle gracefully
      return null;
    }
  }

  Future<void> _handleUnaccept() async {
    if (_isUnaccepting) return;

    final navigator = Navigator.of(context);
    final appLocalizations = AppLocalizations.of(context);

    // --- PENALTY LOGIC ---
    bool proceed = true; // Default to proceed without dialog
    String? dialogTitle;
    String? dialogContent;

    // Use the end of the service window as the measuring stick
    final jobEndTime = _parseJobServiceWindowEnd(widget.job);
    if (jobEndTime != null) {
      final timeUntilEnd = jobEndTime.difference(DateTime.now());

      // High impact: < 3 hours before the window closes
      if (timeUntilEnd.inHours < 3) {
        proceed = false;
        dialogTitle = appLocalizations.unacceptJobHighImpactTitle;
        dialogContent = appLocalizations.unacceptJobHighImpactBody;
      }
      // Low impact: > 3 hours but < 24 hours before the window closes
      else if (timeUntilEnd.inHours < 24) {
        proceed = false;
        dialogTitle = appLocalizations.unacceptJobConfirmTitle;
        dialogContent = appLocalizations.unacceptJobLowImpactBody;
      }
    }

    if (!proceed) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(dialogTitle!),
          content: Text(dialogContent!),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(appLocalizations.unacceptJobBackButton),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(appLocalizations.unacceptJobConfirmButton),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    // --- END PENALTY LOGIC ---

    setState(() => _isUnaccepting = true);

    final wasSuccess = await ref
        .read(jobsNotifierProvider.notifier)
        .unacceptJob(widget.job.instanceId);

    // On failure, the global listener handles the snackbar.
    // On success, we pop the sheet.
    if (mounted) {
      if (wasSuccess) {
        navigator.pop();
      } else {
        // Just reset the UI state on failure
        setState(() => _isUnaccepting = false);
      }
    }
  }

  /// The final, correct logic to start a job with perfect transitions.
  Future<void> _handleStartJob() async {
    if (_isStartingJob) return;
    setState(() => _isStartingJob = true);

    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);

    // Require precise location before starting a job.
    try {
      final precise = await hasPreciseLocation();
      if (!precise && mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.preciseLocationDialogTitle),
            content: Text(l10n.preciseLocationDialogBody),
            actions: [
              TextButton(
                onPressed: () => navigator.pop(),
                child: Text(l10n.okButtonLabel),
              ),
              FilledButton(
                onPressed: () async {
                  await Geolocator.openAppSettings();
                  if (navigator.canPop()) {
                    navigator.pop();
                  }
                },
                child: Text(l10n.locationDisclosureOpenSettings),
              ),
            ],
          ),
        );
        if (mounted) setState(() => _isStartingJob = false);
        return;
      }
    } catch (_) {}

    // This now returns a nullable JobInstance. The GlobalErrorListener will show
    // the snackbar on failure.
    final updatedJob = await ref
        .read(jobsNotifierProvider.notifier)
        .startJob(widget.job.instanceId);

    // If the job start failed, updatedJob will be null.
    if (updatedJob == null) {
      if (mounted) {
        // Just reset the UI state. The error is handled globally.
        setState(() => _isStartingJob = false);
      }
      return;
    }

    // This block is now only reached on success.
    if (mounted) {
      final warmedMap = await JobMapCache.warmMap(context, updatedJob);
      if (!mounted) {
        setState(() => _isStartingJob = false);
        return;
      }

      final pageToPush = JobInProgressPage(
        job: updatedJob,
        preWarmedMap: warmedMap,
      );

      final id = widget.job.instanceId;
      JobMapCache.detachOverlayFor(id);

      final completer = Completer<void>();
      final entry = OverlayEntry(builder: (_) => Offstage(child: pageToPush));
      Overlay.of(context).insert(entry);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        entry.remove();
        completer.complete();
      });

      await completer.future;
      if (!mounted) {
        setState(() => _isStartingJob = false);
        return;
      }

      navigator.pop();
      final route = JobInProgressSlideRoute(page: pageToPush);
      navigator.push(route);

      // The loading state is implicitly handled by the page transition.
      // If we are still mounted here, it means something went wrong before navigation.
      if (mounted) {
        setState(() => _isStartingJob = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mediaQueryPadding = MediaQuery.of(context).padding;

    return GestureDetector(
      // Conditionally capture vertical drags to prevent sheet dismissal while processing.
      onVerticalDragStart: _isProcessing ? (_) {} : null,
      onVerticalDragUpdate: _isProcessing ? (_) {} : null,
      onVerticalDragEnd: _isProcessing ? (_) {} : null,
      child: PopScope(
        // Prevent dismissal via back button/gesture while processing.
        canPop: !_isProcessing,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && mounted) {
            showAppSnackBar(
              context,
              const Text("Please wait for the operation to complete."),
              displayDuration: const Duration(seconds: 2),
            );
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double maxSheetHeight = constraints.maxHeight * 0.98;
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: maxSheetHeight,
                minWidth: constraints.maxWidth,
                maxWidth: constraints.maxWidth,
              ),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  _isPointerDown = true;
                  _isDraggingSheetViaPointer = false;
                  _activePointerId = e.pointer;
                  _lastPointerY = e.position.dy;
                  _lastPointerX = e.position.dx;
                  _lockedPointerAxis = null;
                  _lastPointerSampleMs = DateTime.now().millisecondsSinceEpoch;
                  _lastPointerVelocityY = 0.0;
                  final bool isAtTopOnDown = !_bodyScrollController.hasClients ||
                      _bodyScrollController.position.pixels <= 0;
                  _gestureBeganAtTop = isAtTopOnDown;
                  _lastGestureBeganAtTop = isAtTopOnDown;
                  if (_dragResetController.isAnimating) _dragResetController.stop();
                },
                onPointerMove: (e) {
                  if (_activePointerId == null || e.pointer != _activePointerId) return;
                  if (_lastPointerY == null) { _lastPointerY = e.position.dy; return; }
                  final dx = _lastPointerX != null ? e.position.dx - _lastPointerX! : 0.0;
                  final dy = e.position.dy - _lastPointerY!;
                  _lastPointerX = e.position.dx;
                  _lastPointerY = e.position.dy;
                  final nowMs = DateTime.now().millisecondsSinceEpoch;
                  final int? lastMs = _lastPointerSampleMs;
                  if (lastMs != null) {
                    final dtMs = nowMs - lastMs;
                    if (dtMs > 0) _lastPointerVelocityY = dy / dtMs * 1000.0;
                  }
                  _lastPointerSampleMs = nowMs;
                  if (_lockedPointerAxis == null) {
                    final adx = dx.abs();
                    final ady = dy.abs();
                    if (adx > 6 || ady > 6) {
                      _lockedPointerAxis = adx > ady ? Axis.horizontal : Axis.vertical;
                    }
                  }
                  if (_lockedPointerAxis == Axis.horizontal) {
                    _lastPointerVelocityY = 0.0; return;
                  }
                  if (dy == 0) return;
                  final bool isAtTop = !_bodyScrollController.hasClients ||
                      _bodyScrollController.position.pixels <= 0;
                  if (dy > 0 && isAtTop && _gestureBeganAtTop) {
                    if (_dragResetController.isAnimating) _dragResetController.stop();
                    _isDraggingSheetViaPointer = true;
                    if (_bodyScrollController.hasClients &&
                        _bodyScrollController.position.pixels != 0.0) {
                      _bodyScrollController.jumpTo(0.0);
                    }
                    _pullDownAccumulated += dy;
                    setState(() { _dragOffset = math.max(0.0, _dragOffset + dy); });
                    return;
                  }
                  if (dy < 0 && _dragOffset > 0) {
                    if (_dragResetController.isAnimating) _dragResetController.stop();
                    if (_bodyScrollController.hasClients &&
                        _bodyScrollController.position.pixels != 0.0) {
                      _bodyScrollController.jumpTo(0.0);
                    }
                    _pullDownAccumulated = math.max(0.0, _pullDownAccumulated + dy);
                    final newOffset = math.max(0.0, _dragOffset + dy);
                    final releaseToContent = newOffset == 0.0;
                    setState(() {
                      _isDraggingSheetViaPointer = !releaseToContent;
                      _dragOffset = newOffset;
                    });
                    return;
                  }
                },
                onPointerUp: (_) => _handlePointerUpOrCancel(),
                onPointerCancel: (_) => _handlePointerUpOrCancel(),
                child: RepaintBoundary(
                  key: _sheetBoundaryKey,
                  child: Transform.translate(
                    offset: Offset(0, _dragOffset),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        12,
                        24,
                        mediaQueryPadding.bottom + 16,
                      ),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(38),
                            blurRadius: 10,
                            offset: const Offset(0, -5),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 50,
                            height: 5,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          // Scrollable body
                          Flexible(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: _handleBodyScrollNotification,
                              child: SingleChildScrollView(
                                controller: _bodyScrollController,
                                physics: (_isDismissing || _isDraggingSheetViaPointer || (_dragOffset > 0 && _isPointerDown))
                                    ? const NeverScrollableScrollPhysics()
                                    : const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      widget.job.property.propertyName,
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.job.property.address,
                                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    Builder(
                                      builder: (context) {
                                        final formattedStartTime =
                                            formatTime(context, widget.job.workerStartTimeHint);
                                        final formattedWindowStart =
                                            formatTime(context, widget.job.workerServiceWindowStart);
                                        final formattedWindowEnd =
                                            formatTime(context, widget.job.workerServiceWindowEnd);
                                        final tiles = <_TileData>[
                                          if (formattedStartTime.isNotEmpty)
                                            _TileData(
                                              icon: Icons.access_time_outlined,
                                              label: appLocalizations.jobAcceptSheetRecommendedStart,
                                              value: formattedStartTime,
                                              spanTwoColumns: true,
                                            ),
                                          if (formattedWindowStart.isNotEmpty && formattedWindowEnd.isNotEmpty)
                                            _TileData(
                                              icon: Icons.hourglass_empty_outlined,
                                              label: appLocalizations.jobAcceptSheetServiceWindow,
                                              value: '$formattedWindowStart - $formattedWindowEnd',
                                              spanTwoColumns: true,
                                            ),
                                          _TileData(
                                            icon: Icons.directions_car_outlined,
                                            label: appLocalizations.jobAcceptSheetHeaderDriveTime,
                                            value: _formatMinutesToHrMin(widget.job.travelMinutes),
                                          ),
                                        ];
                                        return _TwoColumnTiles(tiles: tiles);
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    ViewJobMapButton(job: widget.job),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: () => setState(() => _isExpanded = !_isExpanded),
                                      icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, size: 28),
                                      label: Text(
                                        _isExpanded
                                            ? appLocalizations.acceptedJobsBottomSheetHideDetails
                                            : appLocalizations.acceptedJobsBottomSheetViewDetails,
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: theme.primaryColor,
                                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        splashFactory: NoSplash.splashFactory,
                                      ).copyWith(
                                        overlayColor: WidgetStateProperty.all(Colors.transparent),
                                      ),
                                    ),
                                    AnimatedCrossFade(
                                      firstChild: const SizedBox(width: double.infinity, height: 0),
                                      secondChild: _buildExpandedDetails(context, appLocalizations, theme),
                                      crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                                      duration: const Duration(milliseconds: 200),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          AbsorbPointer(
                            absorbing: _isProcessing,
                            child: _buildActionButtons(appLocalizations),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildExpandedDetails(
    BuildContext context,
    AppLocalizations appLocalizations,
    ThemeData theme,
  ) {
    final List<_TileData> detailTiles = [
      _TileData(
        icon: Icons.attach_money,
        label: appLocalizations.acceptedJobsBottomSheetPayLabel,
        value: '${widget.job.pay.toStringAsFixed(0)} USD',
        color: Colors.green,
      ),
      _TileData(
        icon: Icons.timer_outlined,
        label: appLocalizations.jobAcceptSheetHeaderAvgCompletion,
        value: widget.job.displayTime,
      ),
      _TileData(
        icon: Icons.location_on_outlined,
        label: appLocalizations.acceptedJobsBottomSheetDistanceLabel,
        value: widget.job.distanceLabel,
      ),
      _TileData(
        icon: Icons.apartment_outlined,
        label: appLocalizations.jobAcceptSheetBuildings,
        value:
            '${widget.job.numberOfBuildings} bldg${widget.job.numberOfBuildings == 1 ? '' : 's'}',
      ),
      if (widget.job.numberOfBuildings == 1)
        _TileData(
          icon: Icons.stairs_outlined,
          label: appLocalizations.jobAcceptSheetFloors,
          value: widget.job.floorsLabel,
        ),
      _TileData(
        icon: Icons.home_outlined,
        label: appLocalizations.jobAcceptSheetUnits,
        value: widget.job.totalUnitsLabel,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: _TwoColumnTiles(tiles: detailTiles),
    );
  }

  Widget _buildActionButtons(AppLocalizations appLocalizations) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : _handleStartJob,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black87,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.white70,
            ).copyWith(
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              animationDuration: const Duration(milliseconds: 0),
              enableFeedback: false,
            ),
            icon: _isStartingJob
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(appLocalizations.acceptedJobsBottomSheetStartJobButton),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isProcessing ? null : _handleUnaccept,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade200,
              foregroundColor: Colors.black87,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              disabledBackgroundColor: Colors.grey.shade200,
              disabledForegroundColor: Colors.black38,
            ).copyWith(
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              animationDuration: const Duration(milliseconds: 0),
              enableFeedback: false,
            ),
            icon: _isUnaccepting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black54,
                    ),
                  )
                : const Icon(Icons.delete_outline),
            label: Text(
              _isUnaccepting
                  ? appLocalizations.acceptedJobsBottomSheetUnacceptingButton
                  : appLocalizations.acceptedJobsBottomSheetUnacceptButton,
            ),
          ),
        ),
      ],
    );
  }

  // Removed unused helpers _infoItem and _detailRow
}

// ────────────────────────────────────────────────────────────────────────
//  Tile components (mirroring Job Accept sheet styling)
// ────────────────────────────────────────────────────────────────────────
// Generic tile data
class _TileData {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final bool spanTwoColumns;
  _TileData({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.spanTwoColumns = false,
  });
}

// Two-column responsive tile wrapper
class _TwoColumnTiles extends StatelessWidget {
  final List<_TileData> tiles;
  const _TwoColumnTiles({required this.tiles});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final isNarrow = constraints.maxWidth < 260;
        final columns = isNarrow ? 1 : 2;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: tiles.map((t) {
            final double width = columns == 2 && t.spanTwoColumns
                ? constraints.maxWidth
                : itemWidth;
            return SizedBox(
              width: width,
              child: _StatTile(
                icon: t.icon,
                label: t.label,
                value: t.value,
                color: t.color,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

String _formatMinutesToHrMin(int? minutes) {
  if (minutes == null || minutes <= 0) return 'N/A';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return '$h hr${h == 1 ? '' : 's'}';
  return '$h hr $m min';
}

// Single stat tile
class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = color ?? Colors.black87;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: baseColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: baseColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Route for "View Job Map" button
class CachedMapPopupRoute extends PopupRoute<void> {
  final Widget mapPage;
  final String instanceId;
  CachedMapPopupRoute({required this.mapPage, required this.instanceId});
  final ValueNotifier<bool> _inRoute = ValueNotifier<bool>(true);
  bool _reparented = false;
  @override
  Color get barrierColor => Colors.black54;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => 'Dismiss map';
  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // MODIFIED: Wrap the map page in a Stack to add our own back button.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _inRoute,
            builder: (_, show, _) => show ? mapPage : const SizedBox.shrink(),
          ),
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
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    animation.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && !_reparented) {
        _inRoute.value = false;
        final entry = OverlayEntry(
          maintainState: true,
          builder: (_) => Offstage(child: mapPage),
        );
        Overlay.of(context).insert(entry);
        // Reparent warmed map overlay back into cache to maintain state
        JobMapCache.setReparentedEntry(instanceId, entry);
        _reparented = true;
      }
    });
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final tween = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero);
    return SlideTransition(position: tween.animate(curved), child: child);
  }
}

// NEW: Custom route for the "Start Job" button
class JobInProgressSlideRoute extends PopupRoute<void> {
  final JobInProgressPage page;

  JobInProgressSlideRoute({required this.page});

  @override
  Color? get barrierColor => Colors.black.withAlpha(0);

  @override
  bool get barrierDismissible => false; // Cannot dismiss by tapping outside

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return page;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final tween = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero);
    return SlideTransition(position: tween.animate(curved), child: child);
  }
}
