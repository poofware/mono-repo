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
///   will move / snap the sheet.
/// – The job list scrolls independently.
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
  final bool isLoadingJobs; // Global loading state from JobsNotifier.
  final bool hasLoadedInitialJobs;

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
    required this.hasLoadedInitialJobs,
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

  // Compute a dynamic snap height that fits the given message without truncation
  // by estimating the wrapped text height at runtime and converting to a sheet size fraction.
  double _computeDynamicMessageSnapSize(BuildContext context, String message) {
    final double screenHeight = widget.screenHeight;
    final double screenWidth = MediaQuery.of(context).size.width;

    // Match draggableMessage layout: Center -> Padding(all: 20) -> Text(..., fontSize: 16)
    const double horizontalPadding = 20.0 * 2; // left + right
    const double verticalPadding = 20.0 * 2;   // top + bottom
    final double maxTextWidth = (screenWidth - horizontalPadding).clamp(0.0, screenWidth);

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: message,
        style: TextStyle(
          fontSize: 16,
          color: Colors.grey.shade600,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: Directionality.of(context),
      maxLines: null,
    )
      ..layout(maxWidth: maxTextWidth);

    // Account for line metrics and text scale to avoid clipping descenders.
    final List<LineMetrics> lines = painter.computeLineMetrics();
    final int lineCount = lines.length;
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final double scaledFontSize = textScaler.scale(16);
    final double textScale = scaledFontSize / 16.0;
    final double baseMessageHeight = painter.size.height + verticalPadding;
    final double safetyMarginPerLine = 10.0; // extra room per line
    final double multiLineBonus = (lineCount > 1) ? 12.0 : 0.0; // extra for second+ line
    final double scaleMargin = (textScale > 1.0) ? (textScale - 1.0) * 16.0 : 0.0;
    final double messageContentHeight = baseMessageHeight +
        (lineCount * safetyMarginPerLine) +
        multiLineBonus +
        scaleMargin;

    // Base header height: use the actual configured min sheet size to ensure
    // consistency with how the sheet is laid out at runtime.
    final double headerHeightPx = widget.minChildSize * screenHeight;

    // Add a bit more general margin to cover rounding/layout differences.
    const double safetyMargin = 36.0;

    final double totalDesiredHeightPx = headerHeightPx + messageContentHeight + safetyMargin;
    final double fraction = (totalDesiredHeightPx / screenHeight)
        .clamp(widget.minChildSize, widget.maxChildSize);

    // Fallback to legacy constant if anything goes sideways.
    if (!fraction.isFinite) return _messageSnapHeight;
    return fraction;
  }

  // Controller for the list, to check its scroll position.
  final ScrollController _listScrollController = ScrollController();

  /* ──────────────────────────── Drag helpers ──────────────────────────── */

  void _onDragUpdate(DragUpdateDetails d) {
    if (!widget.sheetController.isAttached) return;

    final delta = -d.delta.dy / widget.screenHeight;
    final newSize = (widget.sheetController.size + delta).clamp(
      widget.minChildSize,
      widget.maxChildSize,
    );
    widget.sheetController.jumpTo(newSize);
  }

  void _onDragEnd(DragEndDetails d) {
    if (!widget.sheetController.isAttached) return;

    final v = d.velocity.pixelsPerSecond.dy;
    double target;

    if (v < _hardFlickUp) {
      target = widget.maxChildSize; // Hard flick up → 85 %
    } else if (v < _softFlickUp) {
      target = 0.40; // Soft flick up → 40 %
    } else if (v > _flickDown) {
      target = widget.minChildSize; // Flick down     → 15 %
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

  // The list view no longer drives the sheet; always allow the list to scroll.
  bool _handleScrollNotification(ScrollNotification notification) => false;

  /* ─────────────────────────────── Build ─────────────────────────────── */

  @override
  Widget build(BuildContext context) {
    final sheetColor = Theme.of(context).cardColor;
    final appLocalizations = widget.appLocalizations;
    final logger = ref.read(appLoggerProvider);

    // Height of onscreen keyboard (0 when hidden). We’ll pad the list with it
    // so items remain scrollable instead of pushing the whole sheet up.
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;

    /* ── State listeners that can resize the sheet ── */
    ref.listen<JobsState>(jobsNotifierProvider, (previous, next) {
      if (previous == null || !widget.sheetController.isAttached) return;

      final bool justStartedLoading =
          !previous.isLoadingOpenJobs && next.isLoadingOpenJobs;
      final bool justFinishedLoading =
          previous.isLoadingOpenJobs && !next.isLoadingOpenJobs;

      if (justStartedLoading) {
        final currentSize = widget.sheetController.size;
        final isAtSnapPoint = widget.snapSizes.any(
          (snap) => (currentSize - snap).abs() < 0.01,
        );

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
          final String message = widget.searchQuery.isNotEmpty
              ? widget.appLocalizations.homePageNoJobsMatchSearch
              : widget.appLocalizations.homePageNoJobsAvailable;
          final double dynamicSize = _computeDynamicMessageSnapSize(context, message);
          widget.sheetController.animateTo(
            dynamicSize,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });

    final bool isOffline = !widget.isOnline;
    final double initialSize = isOffline
        ? _computeDynamicMessageSnapSize(
            context,
            widget.appLocalizations.homePageOfflineMessage,
          )
        : widget.minChildSize;

    return DraggableScrollableSheet(
      controller: widget.sheetController,
      initialChildSize: initialSize,
      minChildSize: widget.minChildSize,
      maxChildSize: widget.maxChildSize,
      snap: false,
      snapSizes: widget.snapSizes,
      builder: (context, scrollController) {
        // Dummy scroller so the outer DraggableScrollableSheet works.
        final dummyScroller = SingleChildScrollView(
          controller: scrollController,
          physics: const NeverScrollableScrollPhysics(),
          child: const SizedBox(height: 0),
        );

        /* ── Build the list body depending on state ── */
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
            padding: EdgeInsets.only(bottom: bottomInset),
            itemExtent: 150,
            itemCount: widget.allDefinitions.length,
            itemBuilder: (_, i) => DefinitionCard(
              definition: widget.allDefinitions[i],
              onViewOnMapPressed: () =>
                  widget.onViewOnMapPressed?.call(widget.allDefinitions[i]),
            ),
          );
        }

        /* ── Render sheet ── */
        return Material(
          color: sheetColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          elevation: 0,
          child: Stack(
            children: [
              dummyScroller,
              Column(
                children: [
                  /* ── Header (drag handle, title, controls) ── */
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (widget.searchFocusNode.hasFocus) {
                        widget.searchFocusNode.unfocus();
                      }
                    },
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
                        /* ── Sort / search / refresh row ── */
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              /* Sort dropdown */
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
                                      borderRadius: BorderRadius.circular(12),
                                      style: TextStyle(
                                        color: widget.isOnline
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onSurface
                                            : Colors.grey.shade400,
                                        fontSize: 15,
                                      ),
                                      items: [
                                        DropdownMenuItem(
                                          value: 'distance',
                                          child: Text(
                                            appLocalizations
                                                .homePageSortByDistance,
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: 'pay',
                                          child: Text(
                                            appLocalizations.homePageSortByPay,
                                          ),
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
                              /* Search / refresh icons */
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
                                                    widget.isOnline &&
                                                            widget
                                                                .hasLoadedInitialJobs
                                                        ? Theme.of(
                                                            context,
                                                          ).primaryColor
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
                                    onPressed:
                                        (widget.isOnline &&
                                            !widget.isLoadingJobs)
                                        ? () {
                                            logger.d(
                                              'JobsSheet: Manual refresh triggered.',
                                            );
                                            ref
                                                .read(
                                                  jobsNotifierProvider.notifier,
                                                )
                                                .refreshOnlineJobsIfActive();
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        /* ── Search bar (optional) ── */
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.fastOutSlowIn,
                          child: widget.showSearchBar
                              ? Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    12,
                                  ),
                                  child: TextField(
                                    controller: widget.searchController,
                                    focusNode: widget.searchFocusNode,
                                    decoration: InputDecoration(
                                      hintText:
                                          appLocalizations.homePageSearchHint,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Theme.of(context).primaryColor,
                                        ),
                                      ),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                      suffixIcon: widget.searchQuery.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.clear,
                                                size: 20,
                                              ),
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
                  /* ── List body ── */
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
