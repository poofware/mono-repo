// worker-app/lib/features/jobs/presentation/widgets/jobs_sheet_widget.dart
//
// Entire file — drop‑in replacement. 2025‑07‑16

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/features/jobs/state/jobs_state.dart';
import '../../data/models/job_models.dart';
import '../../providers/jobs_provider.dart';
import 'definition_card_widget.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';

/// Draggable / flick‑able bottom‑sheet that shows open jobs.
///
/// * Vertical drag on header or toolbar behaves as before (tracks finger,
///   then snaps).
/// * Inside the list normal scrolling is preserved.
/// * Extra behaviour:  
///   – If the list is **already at offset 0** and the user gives it a quick
///     **down‑flick** (> 750 px/s), the whole sheet collapses to its minimum
///     height (same as flicking the header).  
///   – A slow pull‑down or iOS bounce at the top does **not** drag the sheet.
class JobsSheet extends ConsumerStatefulWidget {
  final AppLocalizations appLocalizations;
  final DraggableScrollableController sheetController;
  final double minChildSize;
  final double maxChildSize;
  final List<double> snapSizes;
  final double screenHeight;

  final List<DefinitionGroup> allDefinitions;
  final bool isOnline;
  final bool isTestMode;
  final bool isLoadingJobs;

  final String sortBy;
  final ValueChanged<String> onSortChanged;

  final bool showSearchBar;
  final VoidCallback toggleSearchBar;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  final ValueChanged<DefinitionGroup>? onViewOnMapPressed;

  const JobsSheet({
    super.key,
    required this.appLocalizations,
    required this.sheetController,
    required this.minChildSize,
    required this.maxChildSize,
    required this.snapSizes,
    required this.screenHeight,
    required this.allDefinitions,
    required this.isOnline,
    required this.isTestMode,
    required this.isLoadingJobs,
    required this.sortBy,
    required this.onSortChanged,
    required this.showSearchBar,
    required this.toggleSearchBar,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.searchController,
    required this.searchFocusNode,
    this.onViewOnMapPressed,
  });

  @override
  ConsumerState<JobsSheet> createState() => _JobsSheetState();
}

class _JobsSheetState extends ConsumerState<JobsSheet> {
  // Velocity thresholds (logical px / s) that decide snapping.
  static const _hardFlickUp = -1500;
  static const _softFlickUp = -750;
  static const _flickDown   =  750;

  // Height used to show “no jobs / offline” messages.
  static const double _messageSnapHeight = 0.23;

  final ScrollController _listScrollController = ScrollController();

  bool _isAnimatingSheet = false;

  // Manual velocity fallback when DragEndDetails is null.
  bool     _isDragging          = false;
  double   _lastScrollPosition  = 0;
  DateTime _lastScrollTime      = DateTime.now();
  double   _calculatedVelocity  = 0;

  // ───────────────────────────────────────────────────────── Sheet helpers ──
  void _onDragUpdate(DragUpdateDetails d) {
    if (!widget.sheetController.isAttached) return;

    final delta = -d.delta.dy / widget.screenHeight;
    final newSize = (widget.sheetController.size + delta)
        .clamp(widget.minChildSize, widget.maxChildSize);
    widget.sheetController.jumpTo(newSize);
  }

  void _onDragEnd(DragEndDetails d) {
    if (!widget.sheetController.isAttached) return;

    final v = d.velocity.pixelsPerSecond.dy;
    double target;

    if (v < _hardFlickUp) {
      target = widget.maxChildSize; // hard flick up → 85 %
    } else if (v < _softFlickUp) {
      target = 0.40;                // soft flick up → 40 %
    } else if (v > _flickDown) {
      target = widget.minChildSize; // flick down    → min
    } else {
      // Snap to nearest preset.
      final now = widget.sheetController.size;
      target = widget.snapSizes.reduce(
        (a, b) => (a - now).abs() < (b - now).abs() ? a : b,
      );
    }

    _animateSheetTo(target);
  }

  void _animateSheetTo(double target) {
    if (_isAnimatingSheet) return;

    _isAnimatingSheet = true;
    widget.sheetController
        .animateTo(
          target.clamp(widget.minChildSize, widget.maxChildSize),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _isAnimatingSheet = false);
  }

  // Is the inner list scrolled to its very top?
  bool _isListAtTop() {
    return !_listScrollController.hasClients ||
        _listScrollController.position.pixels <= 0;
  }

  // ──────────────────────────────── List scroll handling ──
  bool _handleScrollNotification(ScrollNotification n) {
    // Track velocity manually for the rare case DragEndDetails == null.
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _isDragging         = true;
      _lastScrollPosition = _listScrollController.position.pixels;
      _lastScrollTime     = DateTime.now();
    }

    if (n is ScrollUpdateNotification && _isDragging) {
      final now      = DateTime.now();
      final dtMillis = now.difference(_lastScrollTime).inMilliseconds;
      if (dtMillis > 0) {
        final pos      = _listScrollController.position.pixels;
        final dp       = pos - _lastScrollPosition;
        _calculatedVelocity = (dp / dtMillis) * 1000; // px / s
        _lastScrollPosition = pos;
        _lastScrollTime     = now;
      }
    }

    // Finger released.
    if (n is ScrollEndNotification) {
      final dragV = n.dragDetails?.velocity.pixelsPerSecond.dy;
      final v = dragV ?? _calculatedVelocity;

      final bool isDownwardFast =
          // If we have DragEndDetails, downward is +ve.
          (dragV != null && v > _flickDown) ||
          // If we are falling back to manual maths, downward is –ve.
          (dragV == null && v < -_flickDown);

      if (_isListAtTop() && isDownwardFast) {
        _animateSheetTo(widget.minChildSize);
      }

      _isDragging         = false;
      _calculatedVelocity = 0;
    }

    // Overscroll (iOS bounce). `overscroll` is –ve when pulling down at top.
    if (n is OverscrollNotification &&
        _isListAtTop() &&
        n.overscroll < 0 &&
        n.velocity.abs() > _flickDown) {
      _animateSheetTo(widget.minChildSize);
    }

    return false; // let the notification continue bubbling
  }

  // ─────────────────────────────────────────────────────────────── Build ──
  @override
  Widget build(BuildContext context) {
    final sheetColor       = Theme.of(context).cardColor;
    final appLocalizations = widget.appLocalizations;
    final logger           = ref.read(appLoggerProvider);

    // Auto‑adjust sheet height when jobs start / stop loading.
    ref.listen<JobsState>(jobsNotifierProvider, (previous, next) {
      if (previous == null || !widget.sheetController.isAttached) return;

      final startedLoading  =
          !previous.isLoadingOpenJobs &&  next.isLoadingOpenJobs;
      final finishedLoading =
           previous.isLoadingOpenJobs && !next.isLoadingOpenJobs;

      if (startedLoading) {
        final current = widget.sheetController.size;
        final onSnap  = widget.snapSizes
            .any((s) => (current - s).abs() < 0.01);
        if (!onSnap) _animateSheetTo(widget.minChildSize);
      }

      if (finishedLoading && next.isOnline && next.openJobs.isEmpty) {
        _animateSheetTo(_messageSnapHeight);
      }
    });

    final bool   isOffline   = !widget.isOnline;
    final double initialSize = isOffline
        ? _messageSnapHeight
        : widget.minChildSize;

    return DraggableScrollableSheet(
      controller:       widget.sheetController,
      initialChildSize: initialSize,
      minChildSize:     widget.minChildSize,
      maxChildSize:     widget.maxChildSize,
      snap:             true,
      snapSizes:        widget.snapSizes,
      builder: (context, scrollController) {
        // DraggableScrollableSheet needs *its* ScrollController, but we don’t
        // use it – give it to a hidden dummy instead.
        final dummyScroller = SingleChildScrollView(
          controller: scrollController,
          physics:   const NeverScrollableScrollPhysics(),
          child:     const SizedBox(height: 0),
        );

        // Helper to show a central message that’s still draggable.
        Widget draggableMessage(String message) => GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd:   _onDragEnd,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            );

        // Decide what to show inside the sheet.
        late final Widget listBody;
        if (widget.isLoadingJobs && widget.allDefinitions.isEmpty) {
          listBody = const SizedBox.shrink();
        } else if (!widget.isOnline) {
          listBody = draggableMessage(appLocalizations.homePageOfflineMessage);
        } else if (widget.allDefinitions.isEmpty) {
          final msg = widget.searchQuery.isNotEmpty
              ? appLocalizations.homePageNoJobsMatchSearch
              : appLocalizations.homePageNoJobsAvailable;
          listBody = draggableMessage(msg);
        } else {
          // List with NotificationListener to detect flicks.
          listBody = NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: ListView.builder(
              controller: _listScrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemExtent: 150,
              itemCount: widget.allDefinitions.length,
              itemBuilder: (_, i) => DefinitionCard(
                definition: widget.allDefinitions[i],
                onViewOnMapPressed: () =>
                    widget.onViewOnMapPressed?.call(widget.allDefinitions[i]),
              ),
            ),
          );
        }

        return Material(
          color: sheetColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          elevation: 0,
          child: Stack(
            children: [
              dummyScroller,
              Column(
                children: [
                  // ─────────────── Header / toolbar (draggable) ────────────
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd:   _onDragEnd,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 10),
                          child: Column(
                            children: [
                              Container(
                                width: 40,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.grey[350],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                appLocalizations.homePageJobsSheetTitle,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ───────────────────── Sort / search row ────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    appLocalizations.homePageSortByLabel,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 15,
                                      color: widget.isOnline
                                          ? null
                                          : Colors.grey.shade400,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: widget.sortBy,
                                      focusColor: Colors.transparent,
                                      style: TextStyle(
                                        color: widget.isOnline
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                            : Colors.grey.shade400,
                                        fontSize: 15,
                                      ),
                                      items: [
                                        DropdownMenuItem(
                                          value: 'distance',
                                          child: Text(appLocalizations
                                              .homePageSortByDistance),
                                        ),
                                        DropdownMenuItem(
                                          value: 'pay',
                                          child: Text(appLocalizations
                                              .homePageSortByPay),
                                        ),
                                      ],
                                      onChanged: widget.isOnline
                                          ? (v) => v != null
                                              ? widget.onSortChanged(v)
                                              : null
                                          : null,
                                      disabledHint: Text(
                                        widget.sortBy == 'distance'
                                            ? appLocalizations
                                                .homePageSortByDistance
                                            : appLocalizations
                                                .homePageSortByPay,
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      widget.showSearchBar
                                          ? Icons.search_off
                                          : Icons.search,
                                      color: widget.isOnline
                                          ? Colors.grey.shade600
                                          : Colors.grey.shade400,
                                    ),
                                    tooltip: widget.showSearchBar
                                        ? appLocalizations
                                            .homePageSearchCloseTooltip
                                        : appLocalizations
                                            .homePageSearchOpenTooltip,
                                    onPressed: widget.isOnline
                                        ? widget.toggleSearchBar
                                        : null,
                                  ),
                                  IconButton(
                                    icon: widget.isLoadingJobs
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                widget.isOnline
                                                    ? Theme.of(context)
                                                        .primaryColor
                                                    : Colors.grey.shade400,
                                              ),
                                            ),
                                          )
                                        : Icon(
                                            Icons.refresh,
                                            color: widget.isOnline
                                                ? Theme.of(context).primaryColor
                                                : Colors.grey.shade400,
                                          ),
                                    tooltip: appLocalizations
                                        .homePageJobsSheetRefreshTooltip,
                                    onPressed: (widget.isOnline &&
                                            !widget.isLoadingJobs)
                                        ? () {
                                            logger.d(
                                                'JobsSheet: Manual refresh triggered.');
                                            ref
                                                .read(jobsNotifierProvider
                                                    .notifier)
                                                .refreshOnlineJobsIfActive();
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // ───────────────────────────── Search bar ───────────
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.fastOutSlowIn,
                          child: widget.showSearchBar
                              ? Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                  child: TextField(
                                    controller: widget.searchController,
                                    focusNode: widget.searchFocusNode,
                                    decoration: InputDecoration(
                                      hintText: appLocalizations
                                          .homePageSearchHint,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                            color: Colors.grey.shade300),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                            color:
                                                Theme.of(context).primaryColor),
                                      ),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                      suffixIcon: widget.searchQuery.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear,
                                                  size: 20),
                                              onPressed: () {
                                                widget.searchController.clear();
                                                widget.onSearchChanged('');
                                              },
                                            )
                                          : null,
                                    ),
                                    onChanged: widget.onSearchChanged,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  // ─────────────────────────── List / content area ──────────
                  Expanded(child: listBody),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

