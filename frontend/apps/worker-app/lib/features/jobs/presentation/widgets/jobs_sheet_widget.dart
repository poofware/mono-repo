// worker-app/lib/features/jobs/presentation/widgets/jobs_sheet_widget.dart
//
// Entire file — drop-in replacement.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/features/jobs/state/jobs_state.dart';
import '../../data/models/job_models.dart';
import '../../providers/jobs_provider.dart';
import 'definition_card_widget.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';

/// Draggable / flick-able bottom sheet that shows open jobs.
/// – Any vertical drag **anywhere on the header _or_ sort / search bar**
///   will now move / snap the sheet.
/// – The job list scrolls independently. If scrolled to the top, a *new*
///   downward drag on the list will also move the sheet.
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
  final bool
      isLoadingJobs; // This is the global loading state from JobsNotifier

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
  // Velocity thresholds (logical px / sec) that decide snapping.
  static const _hardFlickUp = -1500;
  static const _softFlickUp = -750;
  static const _flickDown = 750;

  // A special, non-snappable height to reveal messages.
  static const double _messageSnapHeight = 0.23;

  // Controller for the list, to check its scroll position.
  final ScrollController _listScrollController = ScrollController();
  // Flag to decide if a gesture should drag the sheet or scroll the list.
  bool _isSheetDragGesture = false;

  void _onDragUpdate(DragUpdateDetails d) {
    if (!widget.sheetController.isAttached) return;

    // Translate the finger movement into a change of sheet size.
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
      target = widget.maxChildSize; // flick hard up → 85 %
    } else if (v < _softFlickUp) {
      target = 0.40; // flick soft up → 40 %
    } else if (v > _flickDown) {
      target = widget.minChildSize; // flick down      → 15 %
    } else {
      // Snap to the nearest preset size.
      final now = widget.sheetController.size;
      target = widget.snapSizes.reduce(
        (a, b) => (a - now).abs() < (b - now).abs() ? a : b,
      );
    }

    widget.sheetController.animateTo(
      target.clamp(widget.minChildSize, widget.maxChildSize),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    // Ignore nested scrollables.
    if (notification.depth > 0) return false;

    // When the list starts moving and is already at its top,
    // treat further downward drags as sheet gestures.
    if (notification is ScrollStartNotification) {
      final atTop = _listScrollController.position.atEdge &&
          _listScrollController.position.pixels == 0;
      if (atTop) _isSheetDragGesture = true;
    }

    // While dragging down, drive the sheet instead of the list.
    if (notification is ScrollUpdateNotification && _isSheetDragGesture) {
      final details = notification.dragDetails;
      if (details != null && details.delta.dy > 0) {
        _onDragUpdate(details);
        return true; // consume the event
      } else {
        // An upward move hands control back to the list.
        _isSheetDragGesture = false;
      }
    }

    // Drag finished → snap the sheet.
    if (notification is ScrollEndNotification) {
      if (_isSheetDragGesture) {
        // On iOS the bounce clears dragDetails; fall back to zero velocity.
        final details = notification.dragDetails ??
            DragEndDetails(velocity: Velocity.zero);
        _onDragEnd(details);
      }
      _isSheetDragGesture = false;
    }

    return false; // allow other listeners to run
  }

  @override
  Widget build(BuildContext context) {
    final sheetColor = Theme.of(context).cardColor;
    final appLocalizations = widget.appLocalizations;
    final logger = ref.read(appLoggerProvider);

    ref.listen<JobsState>(jobsNotifierProvider, (previous, next) {
      if (previous == null || !widget.sheetController.isAttached) return;

      final bool justStartedLoading =
          !previous.isLoadingOpenJobs && next.isLoadingOpenJobs;
      final bool justFinishedLoading =
          previous.isLoadingOpenJobs && !next.isLoadingOpenJobs;

      if (justStartedLoading) {
        final currentSize = widget.sheetController.size;
        final isAtSnapPoint =
            widget.snapSizes.any((snap) => (currentSize - snap).abs() < 0.01);

        if (!isAtSnapPoint) {
          widget.sheetController.animateTo(
            widget.minChildSize,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      }

      if (justFinishedLoading) {
        if (next.isOnline && next.openJobs.isEmpty) {
          widget.sheetController.animateTo(
            _messageSnapHeight,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });

    final bool isOffline = !widget.isOnline;
    final double initialSize =
        isOffline ? _messageSnapHeight : widget.minChildSize;

    return DraggableScrollableSheet(
      controller: widget.sheetController,
      initialChildSize: initialSize,
      minChildSize: widget.minChildSize,
      maxChildSize: widget.maxChildSize,
      snap: true,
      snapSizes: widget.snapSizes,
      builder: (context, scrollController) {
        final dummyScroller = SingleChildScrollView(
          controller: scrollController,
          physics: const NeverScrollableScrollPhysics(),
          child: const SizedBox(height: 0),
        );

        Widget listBody;

        Widget draggableMessage(String message) {
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              ),
            ),
          );
        }

        if (widget.isLoadingJobs && widget.allDefinitions.isEmpty) {
          listBody = const SizedBox.shrink();
        } else if (!widget.isOnline) {
          listBody = draggableMessage(appLocalizations.homePageOfflineMessage);
        } else if (widget.allDefinitions.isEmpty) {
          final message = widget.searchQuery.isNotEmpty
              ? appLocalizations.homePageNoJobsMatchSearch
              : appLocalizations.homePageNoJobsAvailable;
          listBody = draggableMessage(message);
        } else {
          listBody = ListView.builder(
            controller: _listScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemExtent: 150,
            itemCount: widget.allDefinitions.length,
            itemBuilder: (_, i) => DefinitionCard(
              definition: widget.allDefinitions[i],
              onViewOnMapPressed: () =>
                  widget.onViewOnMapPressed?.call(widget.allDefinitions[i]),
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
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
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
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(appLocalizations.homePageSortByLabel,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 15)),
                                  const SizedBox(width: 8),
                                  DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: widget.sortBy,
                                      focusColor: Colors.transparent,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                          fontSize: 15),
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
                                      onChanged: (v) => v != null
                                          ? widget.onSortChanged(v)
                                          : null,
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
                                      color: Colors.grey.shade600,
                                    ),
                                    tooltip: widget.showSearchBar
                                        ? appLocalizations
                                            .homePageSearchCloseTooltip
                                        : appLocalizations
                                            .homePageSearchOpenTooltip,
                                    onPressed: widget.toggleSearchBar,
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
                                      hintText:
                                          appLocalizations.homePageSearchHint,
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
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _handleScrollNotification,
                      child: listBody,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
