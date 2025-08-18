import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
// worker-app/lib/features/jobs/presentation/widgets/job_accept_sheet.dart
// worker-app/lib/features/jobs/presentation/widgets/job_accept_sheet.dart
//
// UI refresh: modern card header, aggregated stats.
// Adapted to be shown in a modal bottom sheet.
// Includes comprehensive details for selected instance, improved UI, and fixed accept button.
// Pay icon restored, dollar sign removed from text value, "USD" unit added. Start time formatted to AM/PM.
// Accept button has more bottom padding.
// No job instance is auto-selected on open; user must tap a day on the carousel.
// Sheet height animates when an instance is selected. Header stats are now in a single row, evenly spaced.
// Carousel will not pre-highlight a day if no instance is selected.
// Refined AnimatedSwitcher to reduce flicker.
// Added full sheet dimming and loading indicator during job acceptance.
// Sheet now closes only if the accepted job was the last available instance in the group.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';
// removed dynamic overlay provider usage
import 'package:poof_worker/features/jobs/presentation/widgets/date_carousel_widget.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';
import 'info_widgets.dart';
import 'job_map_cache.dart';
import 'view_job_map_button.dart';

class JobAcceptSheet extends ConsumerStatefulWidget {
  final DefinitionGroup definition;
  const JobAcceptSheet({super.key, required this.definition});

  @override
  ConsumerState<JobAcceptSheet> createState() => _JobAcceptSheetState();
}

class _JobAcceptSheetState extends ConsumerState<JobAcceptSheet>
    with TickerProviderStateMixin {
  final GlobalKey _sheetBoundaryKey = GlobalKey();
  // Track the date carousel's bounds to exclude it from background taps
  final GlobalKey _carouselKey = GlobalKey();
  // Exclude other tappable controls (e.g., map button)
  final GlobalKey _viewMapButtonKey = GlobalKey();
  bool _lastTapWasInsideCarousel = false;
  bool _lastTapWasInsideExcluded = false;
  late DateTime _carouselInitialDate;
  JobInstance? _selectedInstance;
  bool _isAccepting = false;
  final ScrollController _bodyScrollController = ScrollController();
  bool _isDismissing = false;
  double _pullDownAccumulated = 0.0;
  // Dynamic distance threshold is computed per device size; see _dismissDistancePx.
  static const double _dismissFlingVelocity =
      340.0; // px/sec (still light, less aggressive)
  static const double _microDismissOffsetPx =
      12.0; // tiny pull, slightly higher
  static const double _microDismissVelocity = 260.0; // moderate quick flick
  double _dragOffset = 0.0; // interactive visual offset for the whole sheet
  late final AnimationController _dragResetController;
  Animation<double>? _dragResetAnimation;
  bool _isPointerDown = false; // used in pointer handlers to manage snap-back
  Timer? _snapBackDebounce;
  // Pointer-driven capture to ensure reversing direction moves the sheet, not content.
  bool _isDraggingSheetViaPointer = false;
  int? _activePointerId;
  double? _lastPointerY;
  double? _lastPointerX;
  Axis? _lockedPointerAxis;
  int? _lastPointerSampleMs;
  double _lastPointerVelocityY = 0.0;
  bool _isAnimatingDismissOut = false;
  bool _isRoutePopping = false;
  bool _didRequestRoutePop = false;
  Timer? _dismissSafetyTimer;
  OverlayEntry? _dismissOverlayEntry;
  AnimationController? _dismissOverlayController;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _carouselInitialDate = DateTime(now.year, now.month, now.day);
    // Cancel any pending eviction for the representative instance on open.
    if (widget.definition.instances.isNotEmpty) {
      final rep = widget.definition.instances.first;
      JobMapCache.cancelEvict(rep.instanceId);
    }
    _dragResetController =
        AnimationController(
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
              if (!_isAnimatingDismissOut) {
                // Ensure we end exactly at zero; prevents half-open residue.
                if (_dragOffset != 0.0) {
                  setState(() => _dragOffset = 0.0);
                }
              }
              _isAnimatingDismissOut = false;
            }
          });
  }

  bool _isGlobalPositionInside(GlobalKey key, Offset globalPosition) {
    final RenderBox? box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final Offset topLeft = box.localToGlobal(Offset.zero);
    final Rect rect = topLeft & box.size;
    return rect.contains(globalPosition);
  }

  void _updateTapInsideCarouselFromGlobal(Offset globalPosition) {
    final bool inCarousel = _isGlobalPositionInside(
      _carouselKey,
      globalPosition,
    );
    final bool inViewMap = _isGlobalPositionInside(
      _viewMapButtonKey,
      globalPosition,
    );
    _lastTapWasInsideCarousel = inCarousel;
    _lastTapWasInsideExcluded = inCarousel || inViewMap;
  }

  @override
  void dispose() {
    _bodyScrollController.dispose();
    // Schedule eviction on close for representative instance, matching accepted sheet.
    if (widget.definition.instances.isNotEmpty) {
      final rep = widget.definition.instances.first;
      JobMapCache.scheduleEvict(rep.instanceId);
    }
    _snapBackDebounce?.cancel();
    _dismissSafetyTimer?.cancel();
    try {
      _dismissOverlayController?.dispose();
    } catch (_) {}
    try {
      _dismissOverlayEntry?.remove();
    } catch (_) {}
    _dragResetController.dispose();
    super.dispose();
  }

  void _requestPopOnce() {
    if (_didRequestRoutePop) return;
    _didRequestRoutePop = true;
    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  void _animateDragOffsetToZero() {
    if (_isDismissing) return;
    if (_dragOffset == 0.0) return;
    final begin = _dragOffset;
    _dragResetAnimation = Tween<double>(begin: begin, end: 0.0).animate(
      CurvedAnimation(parent: _dragResetController, curve: Curves.easeOutCubic),
    );
    // Start the animation on the next frame to avoid setState during layout.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _dragResetController.stop();
      _dragResetController.value = 0.0;
      _dragResetController.forward();
    });
  }

  void _animateDismissWithVelocityAndPop(double releaseVelocityY) {
    if (_isDismissing) return;
    _isDismissing = true;
    _dismissWithOverlay(releaseVelocityY);
  }

  Future<void> _dismissWithOverlay(double releaseVelocityY) async {
    final BuildContext? boundaryContext = _sheetBoundaryKey.currentContext;
    if (boundaryContext == null) {
      if (mounted && !_isRoutePopping) setState(() => _isRoutePopping = true);
      _requestPopOnce();
      return;
    }
    ui.Image? image;
    try {
      final boundary =
          boundaryContext.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        image = await boundary.toImage(pixelRatio: dpr);
      }
    } catch (_) {}

    // Insert overlay with captured image (non-interactive), then pop route immediately.
    if (mounted && !_isRoutePopping) setState(() => _isRoutePopping = true);

    if (image != null && mounted) {
      _dismissOverlayController?.dispose();
      _dismissOverlayController = AnimationController(vsync: this);
      final screenHeight = MediaQuery.of(context).size.height;
      // Derive duration from velocity, clamp to a slightly slower, pleasing range
      final double v = releaseVelocityY.isFinite ? releaseVelocityY.abs() : 0.0;
      final double effectiveV = v > 0.0 ? v : _dismissFlingVelocity;
      double durationMs = (screenHeight / (effectiveV + 300.0)) * 1000.0;
      durationMs *= 1.12; // tiny slow-down for a less "vanishy" feel
      if (durationMs < 160.0) durationMs = 160.0; // was 140ms
      if (durationMs > 280.0) durationMs = 280.0; // was 260ms
      _dismissOverlayController!.duration = Duration(
        milliseconds: durationMs.round(),
      );

      final animation = CurvedAnimation(
        parent: _dismissOverlayController!,
        curve: Curves.linearToEaseOut,
      );

      _dismissOverlayEntry?.remove();
      _dismissOverlayEntry = OverlayEntry(
        maintainState: false,
        builder: (ctx) {
          return IgnorePointer(
            ignoring: true,
            child: AnimatedBuilder(
              animation: animation,
              builder: (BuildContext context, Widget? child) {
                final dy = animation.value * (screenHeight + 60.0);
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: RawImage(image: image),
                  ),
                );
              },
            ),
          );
        },
      );
      Overlay.of(context).insert(_dismissOverlayEntry!);
    }

    _requestPopOnce();

    if (_dismissOverlayController != null) {
      try {
        await _dismissOverlayController!.forward();
      } catch (_) {}
      try {
        _dismissOverlayEntry?.remove();
        _dismissOverlayEntry = null;
      } catch (_) {}
    }
  }

  double _dismissDistancePx(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = screenHeight * 0.95; // match layout constraint
    final raw =
        maxSheetHeight * 0.10; // 10% of sheet height (slightly less aggressive)
    if (raw < 36.0) return 36.0;
    if (raw > 84.0) return 84.0;
    return raw;
  }

  // Debounce has been disabled in favor of pointer-up decision logic.

  void _handlePointerUpOrCancel() {
    if (!mounted || _isDismissing) return;
    _snapBackDebounce?.cancel();
    final bool isAtTop =
        !_bodyScrollController.hasClients ||
        _bodyScrollController.position.pixels <= 0;
    final bool shouldDismissByVelocity =
        isAtTop &&
        _lockedPointerAxis != Axis.horizontal &&
        _lastPointerVelocityY >= _dismissFlingVelocity;
    final bool shouldDismissByMicroFlick =
        isAtTop &&
        _lockedPointerAxis != Axis.horizontal &&
        (_dragOffset >= _microDismissOffsetPx ||
            _pullDownAccumulated >= _microDismissOffsetPx) &&
        _lastPointerVelocityY >= _microDismissVelocity;
    if (_dragOffset > 0.0 ||
        shouldDismissByVelocity ||
        shouldDismissByMicroFlick) {
      final bool shouldDismissByOffset =
          _dragOffset >= _dismissDistancePx(context);
      if (shouldDismissByVelocity ||
          shouldDismissByOffset ||
          shouldDismissByMicroFlick) {
        if (_dragResetController.isAnimating) {
          _dragResetController.stop();
        }
        _animateDismissWithVelocityAndPop(_lastPointerVelocityY);
      } else {
        // Snap back immediately since we may have suppressed scroll notifications.
        _animateDragOffsetToZero();
      }
    }
    _pullDownAccumulated = 0.0;
    _isPointerDown = false;
    _isDraggingSheetViaPointer = false;
    _activePointerId = null;
    _lastPointerY = null;
    _lastPointerX = null;
    _lockedPointerAxis = null;
    _lastPointerSampleMs = null;
    _lastPointerVelocityY = 0.0;
  }

  bool _handleBodyScrollNotification(ScrollNotification notification) {
    if (_isDismissing) return false;
    // Ignore horizontal scroll notifications (e.g., from DateCarousel)
    final dir = notification.metrics.axisDirection;
    if (dir == AxisDirection.left || dir == AxisDirection.right) {
      return false;
    }
    // While the user's finger is actively dragging the sheet, avoid applying
    // scroll-based deltas too (prevents double movement and keeps 1:1 feel).
    if (_isPointerDown) return false;

    // Stop any ongoing reset animation at the start of a new user drag.
    if (notification is ScrollStartNotification) {
      if (_dragResetController.isAnimating) {
        _dragResetController.stop();
      }
      _snapBackDebounce?.cancel();
    }

    final bool isAtTop =
        !_bodyScrollController.hasClients ||
        _bodyScrollController.position.pixels <= 0;

    // iOS-style bounce overscroll accumulates distance while pulling down.
    if (notification is OverscrollNotification) {
      if (isAtTop && notification.overscroll < 0) {
        final delta = -notification.overscroll;
        _pullDownAccumulated += delta;
        // Move the whole sheet down with the finger.
        if (_dragResetController.isAnimating) {
          _dragResetController.stop();
        }
        setState(() {
          _dragOffset = math.max(0.0, _dragOffset + delta);
        });
        // No snap while finger held; defer to pointer-up
        return false; // keep bounce behavior
      }
    }

    // Android clamping: accumulate downward delta at top.
    if (notification is ScrollUpdateNotification) {
      final double? delta = notification.scrollDelta;
      if (isAtTop && (delta != null)) {
        if (delta < 0) {
          // Pulling down
          final d = -delta;
          _pullDownAccumulated += d;
          if (_dragResetController.isAnimating) {
            _dragResetController.stop();
          }
          setState(() {
            _dragOffset = math.max(0.0, _dragOffset + d);
          });
          // No snap while finger held
        } else if (delta > 0 && _dragOffset > 0) {
          // Pushing up while offset is applied: reduce offset
          // Keep inner content pinned at the top while we track the finger back up.
          if (_bodyScrollController.hasClients &&
              _bodyScrollController.position.pixels != 0.0) {
            _bodyScrollController.jumpTo(0.0);
          }
          setState(() {
            _dragOffset = math.max(0.0, _dragOffset - delta);
          });
          // No snap while finger held
        }
        return false;
      } else if (!isAtTop && _dragOffset != 0.0) {
        // If we are no longer at top, reset only when finger is not down
        if (!_isPointerDown) {
          setState(() => _dragOffset = 0.0);
        }
      }
    }

    // Decide on end of drag (or ballistic stop).
    if (notification is ScrollEndNotification) {
      final double velocityY =
          notification.dragDetails?.velocity.pixelsPerSecond.dy ?? 0.0;
      final double threshold = _dismissDistancePx(context);
      final bool passedDistance = _pullDownAccumulated >= threshold;
      final bool passedVelocity = velocityY >= _dismissFlingVelocity;
      final bool distanceByOffset = _dragOffset >= threshold;
      // If velocity alone triggers dismissal but offset is tiny, avoid visual snap-up.
      // In that case, keep the current offset and dismiss immediately.
      if (isAtTop && (passedVelocity || passedDistance || distanceByOffset)) {
        _snapBackDebounce?.cancel();
        if (_dragResetController.isAnimating) {
          _dragResetController.stop();
        }
        _animateDismissWithVelocityAndPop(velocityY);
      } else {
        // Only snap back if finger is up and velocity is low.
        _snapBackDebounce?.cancel();
        if (!_isPointerDown) {
          _animateDragOffsetToZero();
        }
      }
      _pullDownAccumulated = 0.0;
      return false;
    }

    // Reset accumulation when scrolling up away from the top.
    if (notification is ScrollUpdateNotification) {
      final double? delta = notification.scrollDelta;
      if (delta != null && delta > 0) {
        _pullDownAccumulated = 0.0;
      }
    }

    return false;
  }

  void _updateSelectedInstance(DateTime day) {
    // Use live definition data so newly paginated instances are included
    final currentOpenJobs = ref.read(jobsNotifierProvider).openJobs;
    final currentDefinitionGroups = groupOpenJobs(currentOpenJobs);
    final liveDefinition = currentDefinitionGroups.firstWhere(
      (dg) => dg.definitionId == widget.definition.definitionId,
      orElse: () => widget.definition,
    );
    final match = liveDefinition.instances.where(
      (inst) => _isSameDate(parseYmd(inst.serviceDate), day),
    );
    _selectedInstance = match.isEmpty ? null : match.first;
  }

  void _handleDateSelected(DateTime day) {
    setState(() {
      _carouselInitialDate = day;
      _updateSelectedInstance(day);
    });
  }

  Future<void> _acceptSelectedInstance() async {
    if (_selectedInstance == null || _isAccepting) return;

    // --- Capture context-sensitive objects BEFORE async gaps ---
    final navigator = Navigator.of(context);
    final logger = ref.read(appLoggerProvider);

    // --- Check if this is the last instance in the current group ---
    final currentOpenJobsBeforeAccept = ref.read(jobsNotifierProvider).openJobs;
    final currentDefinitionGroupsBeforeAccept = groupOpenJobs(
      currentOpenJobsBeforeAccept,
    );
    final liveDefinitionBeforeAccept = currentDefinitionGroupsBeforeAccept
        .firstWhere(
          (dg) => dg.definitionId == widget.definition.definitionId,
          orElse: () => widget
              .definition, // Fallback, though should ideally always find it
        );
    final bool wasLastInstanceInGroup =
        liveDefinitionBeforeAccept.instances.length == 1 &&
        liveDefinitionBeforeAccept.instances.first.instanceId ==
            _selectedInstance!.instanceId;
    // ---

    setState(() => _isAccepting = true);
    logger.d(
      'User initiated accept for instance: ${_selectedInstance!.instanceId}',
    );

    // The notifier now returns a boolean. The GlobalErrorListener handles failure snackbars.
    final bool wasSuccess = await ref
        .read(jobsNotifierProvider.notifier)
        .acceptJob(_selectedInstance!.instanceId);

    // This block now runs regardless of success or failure.
    if (mounted) {
      setState(() => _isAccepting = false);
    } else {
      // If the widget is unmounted, we can't do anything else.
      return;
    }

    if (wasSuccess) {
      logger.i(
        'Instance ${_selectedInstance!.instanceId} accepted successfully via notifier.',
      );

      // Check state *after* acceptance
      final currentOpenJobsAfterAccept = ref
          .read(jobsNotifierProvider)
          .openJobs;
      final currentDefinitionGroupsAfterAccept = groupOpenJobs(
        currentOpenJobsAfterAccept,
      );

      final definitionGroupStillExists = currentDefinitionGroupsAfterAccept.any(
        (group) => group.definitionId == widget.definition.definitionId,
      );

      bool shouldCloseSheet = false;
      if (wasLastInstanceInGroup) {
        // If it was the last instance, the group should now be empty or gone.
        if (!definitionGroupStillExists) {
          shouldCloseSheet = true;
        } else {
          // Check if the group still exists but its instances list is now empty
          final updatedGroup = currentDefinitionGroupsAfterAccept.firstWhere(
            (group) => group.definitionId == widget.definition.definitionId,
          );
          if (updatedGroup.instances.isEmpty) {
            shouldCloseSheet = true;
          }
        }
      }

      if (shouldCloseSheet) {
        if (mounted) {
          logger.d('Accepted the last instance, closing sheet.');
          navigator.pop();
        }
      } else {
        // If the group still exists but the specific accepted instance is gone, clear selection
        final liveDefinitionAfterAccept = currentDefinitionGroupsAfterAccept
            .firstWhere(
              (dg) => dg.definitionId == widget.definition.definitionId,
              orElse: () => DefinitionGroup(
                definitionId: '',
                propertyName: '',
                propertyAddress: '',
                distanceMiles: 0,
                pay: 0,
                transportMode: TransportMode.walk,
                instances: [],
              ), // Dummy if group disappeared unexpectedly
            );
        if (!liveDefinitionAfterAccept.instances.any(
          (inst) => inst.instanceId == _selectedInstance?.instanceId,
        )) {
          if (mounted) {
            setState(() {
              _selectedInstance = null;
            });
          }
        }
      }
    }
    // No 'else' block needed, as the GlobalErrorListener handles failure UI.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final appLocalizations = AppLocalizations.of(context);
    final mediaQueryPadding = MediaQuery.of(context).padding;
    // Revert: remove dynamic bottom gap behavior

    final currentOpenJobs = ref.watch(
      jobsNotifierProvider.select((s) => s.openJobs),
    );
    final currentDefinitionGroups = groupOpenJobs(currentOpenJobs);
    final liveDefinition = currentDefinitionGroups.firstWhere(
      (dg) => dg.definitionId == widget.definition.definitionId,
      orElse: () => widget.definition,
    );

    final isCarouselDateActuallySelected =
        _selectedInstance != null &&
        liveDefinition.instances.any(
          (inst) =>
              inst.instanceId == _selectedInstance!.instanceId &&
              _isSameDate(parseYmd(inst.serviceDate), _carouselInitialDate),
        );

    // Note: Buildings and units info now always visible

    // Determine dates for carousel.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.add(const Duration(days: -1));

    // Check if any job in this definition group is for yesterday.
    final bool hasJobYesterday = liveDefinition.instances.any(
      (inst) => _isSameDate(parseYmd(inst.serviceDate), yesterday),
    );

    // The carousel starts from yesterday if there's a job on that day, otherwise today.
    final DateTime carouselStartDate = hasJobYesterday ? yesterday : today;

    // Find the latest instance date for this group to ensure the carousel extends far enough.
    DateTime latestInstanceDate = today;
    if (liveDefinition.instances.isNotEmpty) {
      latestInstanceDate = liveDefinition.instances
          .map((inst) => parseYmd(inst.serviceDate))
          .reduce((a, b) => a.isAfter(b) ? a : b);
    }

    // Default end date is 7 days from today.
    final defaultEndDate = today.add(const Duration(days: 7));
    final carouselEndDate = latestInstanceDate.isAfter(defaultEndDate)
        ? latestInstanceDate
        : defaultEndDate;

    // Calculate total days from the dynamic start date to the calculated end date.
    final dayCount = carouselEndDate.difference(carouselStartDate).inDays + 1;
    final carouselDates = List.generate(
      dayCount,
      (i) => carouselStartDate.add(Duration(days: i)),
    );

    // Sheet height: dynamic with a cap (max 98% of screen)
    final double maxSheetHeight = MediaQuery.of(context).size.height * 0.98;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
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
            if (_dragResetController.isAnimating) {
              _dragResetController.stop();
            }
            _snapBackDebounce?.cancel();
          },
          onPointerMove: (e) {
            if (_isDismissing) return;
            if (_activePointerId == null || e.pointer != _activePointerId)
              return;
            if (_lastPointerY == null) {
              _lastPointerY = e.position.dy;
              return;
            }
            final dx = _lastPointerX != null
                ? e.position.dx - _lastPointerX!
                : 0.0;
            final dy = e.position.dy - _lastPointerY!;
            _lastPointerX = e.position.dx;
            _lastPointerY = e.position.dy;
            // Track simple velocity for flick-to-dismiss
            final nowMs = DateTime.now().millisecondsSinceEpoch;
            final int? lastMs = _lastPointerSampleMs;
            if (lastMs != null) {
              final int dtMs = nowMs - lastMs;
              if (dtMs > 0) {
                _lastPointerVelocityY = dy / dtMs * 1000.0; // px/s
              }
            }
            _lastPointerSampleMs = nowMs;

            // Lock gesture axis after a small slop so horizontal drags never move the sheet.
            if (_lockedPointerAxis == null) {
              final adx = dx.abs();
              final ady = dy.abs();
              if (adx > 6 || ady > 6) {
                _lockedPointerAxis = adx > ady
                    ? Axis.horizontal
                    : Axis.vertical;
              }
            }
            if (_lockedPointerAxis == Axis.horizontal) {
              // Ensure horizontal swipes can't produce a stale vertical velocity.
              _lastPointerVelocityY = 0.0;
              return;
            }
            if (dy == 0) return;
            final bool isAtTop =
                !_bodyScrollController.hasClients ||
                _bodyScrollController.position.pixels <= 0;

            // Capture downward drags at top to move the whole sheet.
            if (dy > 0 && isAtTop) {
              if (_dragResetController.isAnimating) {
                _dragResetController.stop();
              }
              _isDraggingSheetViaPointer = true;
              if (_bodyScrollController.hasClients &&
                  _bodyScrollController.position.pixels != 0.0) {
                _bodyScrollController.jumpTo(0.0);
              }
              _pullDownAccumulated += dy;
              setState(() {
                _dragOffset = math.max(0.0, _dragOffset + dy);
              });
              return;
            }

            // While the sheet is offset, reversing upward should reduce the offset first.
            if (dy < 0 && _dragOffset > 0) {
              if (_dragResetController.isAnimating) {
                _dragResetController.stop();
              }
              if (_bodyScrollController.hasClients &&
                  _bodyScrollController.position.pixels != 0.0) {
                _bodyScrollController.jumpTo(0.0);
              }
              _pullDownAccumulated = math.max(0.0, _pullDownAccumulated + dy);
              final double newOffset = math.max(0.0, _dragOffset + dy);
              final bool willReleaseToContent = newOffset == 0.0;
              setState(() {
                _isDraggingSheetViaPointer = !willReleaseToContent;
                _dragOffset = newOffset;
              });
              return;
            }
          },
          onPointerUp: (_) => _handlePointerUpOrCancel(),
          onPointerCancel: (_) => _handlePointerUpOrCancel(),
          child: Opacity(
            opacity: _isRoutePopping ? 0.0 : 1.0,
            child: RepaintBoundary(
              key: _sheetBoundaryKey,
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(38),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (details) {
                      _updateTapInsideCarouselFromGlobal(
                        details.globalPosition,
                      );
                    },
                    onTap: () {
                      if (_lastTapWasInsideExcluded) return;
                      if (_selectedInstance != null) {
                        setState(() {
                          _selectedInstance = null;
                        });
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header / Drag Handle
                        Padding(
                          padding: const EdgeInsets.only(top: 12.0),
                          child: Container(
                            width: 40,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // This flexible + scroll view holds all content EXCEPT the bottom button.
                        // It will only scroll if the content inside exceeds the space given to it
                        // by the parent Column, which is constrained by the ConstrainedBox.
                        Flexible(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTapDown: (details) {
                              _updateTapInsideCarouselFromGlobal(
                                details.globalPosition,
                              );
                            },
                            onTap: () {
                              if (_lastTapWasInsideCarousel) return;
                              if (_selectedInstance != null) {
                                setState(() {
                                  _selectedInstance = null;
                                });
                              }
                            },
                            child: NotificationListener<ScrollNotification>(
                              onNotification: _handleBodyScrollNotification,
                              child: SingleChildScrollView(
                                controller: _bodyScrollController,
                                physics:
                                    (_isDismissing ||
                                        _isDraggingSheetViaPointer ||
                                        (_dragOffset > 0 && _isPointerDown))
                                    ? const NeverScrollableScrollPhysics()
                                    : const BouncingScrollPhysics(
                                        parent: AlwaysScrollableScrollPhysics(),
                                      ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Header card and stats with standard horizontal padding
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onTap: () {
                                          if (_selectedInstance != null) {
                                            setState(() {
                                              _selectedInstance = null;
                                            });
                                          }
                                        },
                                        child: Card(
                                          color: cardColor,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              20,
                                              16,
                                              20,
                                              10, // slightly tighter bottom padding to reduce gap to carousel
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                GestureDetector(
                                                  behavior: HitTestBehavior
                                                      .translucent,
                                                  onTap: () {
                                                    if (_selectedInstance !=
                                                        null) {
                                                      setState(() {
                                                        _selectedInstance =
                                                            null;
                                                      });
                                                    }
                                                  },
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        liveDefinition
                                                            .propertyName,
                                                        style: const TextStyle(
                                                          fontSize: 24,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        liveDefinition
                                                            .propertyAddress,
                                                        style: TextStyle(
                                                          fontSize: 15,
                                                          color: Colors
                                                              .grey
                                                              .shade700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                // Compact definition-level tiles (no dividing line)
                                                const SizedBox(height: 12),
                                                _DefinitionStatTiles(
                                                  definition: liveDefinition,
                                                  appLocalizations:
                                                      appLocalizations,
                                                  selectedInstance:
                                                      _selectedInstance,
                                                  showAvgPay:
                                                      _selectedInstance == null,
                                                  showAvgTime:
                                                      _selectedInstance == null,
                                                ),
                                                const SizedBox(height: 12),
                                                ViewJobMapButton(
                                                  key: _viewMapButtonKey,
                                                  job:
                                                      liveDefinition
                                                          .instances
                                                          .isNotEmpty
                                                      ? liveDefinition
                                                            .instances
                                                            .first
                                                      : null,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Date carousel should go edge-to-edge (no horizontal padding)
                                    Padding(
                                      // Consistent spacing after buildings/units info
                                      padding: const EdgeInsets.only(top: 8),
                                      child: DateCarousel(
                                        key: _carouselKey,
                                        availableDates: carouselDates,
                                        selectedDate:
                                            isCarouselDateActuallySelected
                                            ? _carouselInitialDate
                                            : DateTime(0),
                                        onDateSelected: _handleDateSelected,
                                        isDayEnabled: (day) =>
                                            liveDefinition.instances.any(
                                              (inst) => _isSameDate(
                                                parseYmd(inst.serviceDate),
                                                day,
                                              ),
                                            ),
                                        leftPadding: 14.0,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    // Removed select-date prompt card
                                    // No extra bottom card; keep layout compact
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Sticky button at the bottom
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            mediaQueryPadding.bottom + 16.0,
                          ),
                          child: WelcomeButton(
                            text: _isAccepting
                                ? appLocalizations.jobAcceptSheetAcceptingButton
                                : appLocalizations.jobAcceptSheetAcceptButton,
                            isLoading: _isAccepting,
                            onPressed:
                                (_selectedInstance == null ||
                                    !liveDefinition.instances.any(
                                      (i) =>
                                          i.instanceId ==
                                          _selectedInstance!.instanceId,
                                    ))
                                ? null
                                : _acceptSelectedInstance,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// (removed) _InstanceDetails: merged into header tiles when a date is selected

// Definition-level compact stats (base state)
class _DefinitionStatTiles extends StatelessWidget {
  final DefinitionGroup definition;
  final AppLocalizations appLocalizations;
  final JobInstance? selectedInstance;
  final bool showAvgPay;
  final bool showAvgTime;
  const _DefinitionStatTiles({
    required this.definition,
    required this.appLocalizations,
    this.selectedInstance,
    this.showAvgPay = true,
    this.showAvgTime = true,
  });
  @override
  Widget build(BuildContext context) {
    final inst = definition.instances.isNotEmpty
        ? definition.instances.first
        : null;
    final start = inst?.workerStartTimeHint ?? '';
    final startFormatted = start.isNotEmpty ? formatTime(context, start) : '';
    final workerWindowStart = inst?.workerServiceWindowStart ?? '';
    final workerWindowEnd = inst?.workerServiceWindowEnd ?? '';
    final windowDisplay =
        (workerWindowStart.isNotEmpty && workerWindowEnd.isNotEmpty)
        ? '${formatTime(context, workerWindowStart)} - ${formatTime(context, workerWindowEnd)}'
        : '';
    final bool isSingleBuilding =
        definition.instances.isNotEmpty &&
        definition.instances.every((i) => i.numberOfBuildings == 1);
    final tiles = <_TileData>[
      if (selectedInstance != null)
        _TileData(
          icon: Icons.attach_money,
          label: appLocalizations.acceptedJobsBottomSheetPayLabel,
          value: '${selectedInstance!.pay.toStringAsFixed(0)} USD',
          color: Colors.green,
        )
      else if (showAvgPay)
        _TileData(
          icon: Icons.attach_money,
          label: 'Avg Pay',
          value: '${definition.pay.toStringAsFixed(0)} USD',
          color: Colors.green,
        ),
      if (selectedInstance != null)
        _TileData(
          icon: Icons.timer_outlined,
          label: appLocalizations.jobAcceptSheetHeaderAvgCompletion,
          value: selectedInstance!.displayTime,
        )
      else if (showAvgTime)
        _TileData(
          icon: Icons.timer_outlined,
          label: appLocalizations.jobAcceptSheetHeaderAvgCompletion,
          value: definition.displayAvgTime,
        ),
      _TileData(
        icon: Icons.directions_car_outlined,
        label: appLocalizations.jobAcceptSheetHeaderDriveTime,
        value: definition.displayAvgTravelTime,
      ),
      if (startFormatted.isNotEmpty)
        _TileData(
          icon: Icons.access_time_outlined,
          label: appLocalizations.jobAcceptSheetRecommendedStart,
          value: startFormatted,
        ),
      if (windowDisplay.isNotEmpty)
        _TileData(
          icon: Icons.hourglass_empty_outlined,
          label: appLocalizations.jobAcceptSheetServiceWindow,
          value: windowDisplay,
          spanTwoColumns: true,
        ),
      _TileData(
        icon: Icons.apartment_outlined,
        label: appLocalizations.jobAcceptSheetBuildings,
        value: _buildBuildingsLabel(definition.instances),
      ),
      if (isSingleBuilding)
        _TileData(
          icon: Icons.stairs_outlined,
          label: appLocalizations.jobAcceptSheetFloors,
          value: _buildFloorsLabel(definition.instances),
        ),
      _TileData(
        icon: Icons.home_outlined,
        label: appLocalizations.jobAcceptSheetUnits,
        value: _buildUnitsLabel(definition.instances),
      ),
    ];
    return _TwoColumnTiles(tiles: tiles);
  }
}

// (removed) Replaced with shared ViewJobMapButton

String _buildBuildingsLabel(List<JobInstance> instances) {
  if (instances.isEmpty) return '—';
  final counts = instances.map((i) => i.numberOfBuildings).where((c) => c > 0);
  if (counts.isEmpty) return '—';
  final minCount = counts.reduce((a, b) => a < b ? a : b);
  final maxCount = counts.reduce((a, b) => a > b ? a : b);
  if (minCount == maxCount) {
    final plural = minCount == 1 ? '' : 's';
    return '$minCount bldg$plural';
  }
  return '$minCount-$maxCount bldgs';
}

String _buildFloorsLabel(List<JobInstance> instances) {
  if (instances.isEmpty) return '—';
  final allFloors = instances
      .expand((i) => i.buildings)
      .expand((b) => b.floors);
  final unique = allFloors.toSet().toList()..sort();
  if (unique.isEmpty) return '—';
  if (unique.length > 2) return '${unique.length} floors';
  return 'fl ${unique.join(', ')}';
}

String _buildUnitsLabel(List<JobInstance> instances) {
  if (instances.isEmpty) return '—';
  // Use the first instance's label as representative
  return instances.first.totalUnitsLabel;
}

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
        final isNarrow = constraints.maxWidth < 360;
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

// (removed) previously used time info tile; unified into generic tiles

DateTime parseYmd(String ymd) {
  final parts = ymd.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

extension NullableObjectExt<T> on T {
  R let<R>(R Function(T it) op) => op(this);
}
