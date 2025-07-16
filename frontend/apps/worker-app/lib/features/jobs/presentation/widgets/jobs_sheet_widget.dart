// worker-app/lib/features/jobs/presentation/widgets/jobs_sheet_widget.dart
//
// Drop-in replacement – July 2025
//

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smooth_sheets/smooth_sheets.dart'; // NEW
// Requires smooth_sheets: ^0.14.0
import 'package:poof_worker/features/jobs/state/jobs_state.dart';
import '../../data/models/job_models.dart';
import '../../providers/jobs_provider.dart';
import 'definition_card_widget.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';

/// ---------------------------------------------------------------------------
///  Custom physics helpers
/// ---------------------------------------------------------------------------

/// Bouncing-style physics (iOS) that ignore **up-ward** drag deltas so the
/// inner `ListView` can scroll, while down-ward drags still collapse the sheet.
class _DownwardOnlyBouncingSheetPhysics extends BouncingSheetPhysics {
  const _DownwardOnlyBouncingSheetPhysics();

  @override
  double applyPhysicsToOffset(double delta, SheetMetrics metrics) =>
      delta > 0 ? 0 : super.applyPhysicsToOffset(delta, metrics);
}

/// Clamping-style physics (Android) that ignore **up-ward** drag deltas.
class _DownwardOnlyClampingSheetPhysics extends ClampingSheetPhysics {
  const _DownwardOnlyClampingSheetPhysics();

  @override
  double applyPhysicsToOffset(double delta, SheetMetrics metrics) =>
      delta > 0 ? 0 : super.applyPhysicsToOffset(delta, metrics);
}

/// ---------------------------------------------------------------------------
///  JobsSheet widget
/// ---------------------------------------------------------------------------

/// Draggable bottom-sheet that shows open jobs.
/// Now powered by **smooth_sheets** for automatic
/// scroll-to-close interaction.
class JobsSheet extends ConsumerStatefulWidget {
  final AppLocalizations appLocalizations;
  final SheetController sheetController;
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
  /// A special, non-snappable height to reveal messages.
  static const double _messageSnapHeight = 0.23;

  // ──────────────────────────────────────────────
  //  Build
  // ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sheetColor = Theme.of(context).cardColor;
    final appLoc   = widget.appLocalizations;
    final logger   = ref.read(appLoggerProvider);

    // Listen for loading-state changes to auto-adjust sheet height.
    ref.listen<JobsState>(jobsNotifierProvider, (prev, next) {
      if (prev == null || !widget.sheetController.hasClient) return;

      final startedLoading  = !prev.isLoadingOpenJobs && next.isLoadingOpenJobs;
      final finishedLoading =  prev.isLoadingOpenJobs && !next.isLoadingOpenJobs;

      if (startedLoading) {
        widget.sheetController.animateTo(
          SheetOffset(widget.minChildSize),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }

      if (finishedLoading && next.isOnline && next.openJobs.isEmpty) {
        widget.sheetController.animateTo(
          SheetOffset(_messageSnapHeight),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });

    final initialSize = widget.isOnline
        ? widget.minChildSize
        : _messageSnapHeight;

    final bool canInteract =
        widget.isOnline && widget.allDefinitions.isNotEmpty;

    // ── Helpers ────────────────────────────────────────────────────
    Widget _draggableMsg(String msg) => Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        );

    // Determine overlay/empty-state message
    String? overlayMessage;
    if (!widget.isOnline) {
      overlayMessage = appLoc.homePageOfflineMessage;
    } else if (!widget.isLoadingJobs && widget.allDefinitions.isEmpty) {
      overlayMessage = widget.searchQuery.isNotEmpty
          ? appLoc.homePageNoJobsMatchSearch
          : appLoc.homePageNoJobsAvailable;
    }

    // ── List / empty-state body ───────────────────────────────────
    final double bottomPadding = 24 + MediaQuery.of(context).padding.bottom;

    Widget bodyWidget;
    if (overlayMessage != null) {
      bodyWidget = Center(child: _draggableMsg(overlayMessage));
    } else {
      bodyWidget = ListView.builder(
        padding: EdgeInsets.only(bottom: bottomPadding),
        itemCount: widget.allDefinitions.length,
        itemBuilder: (_, i) => DefinitionCard(
          definition: widget.allDefinitions[i],
          onViewOnMapPressed: () =>
              widget.onViewOnMapPressed?.call(widget.allDefinitions[i]),
        ),
      );
    }

    // ── Sheet setup ───────────────────────────────────────────────
    final SheetPhysics sheetPhysics = Platform.isIOS
        ? const _DownwardOnlyBouncingSheetPhysics()
        : const _DownwardOnlyClampingSheetPhysics();

    final snapGrid = MultiSnapGrid(
      snaps: widget.snapSizes.map((s) => SheetOffset(s)).toList(),
    );

    return SheetViewport(
      child: Sheet(
        controller: widget.sheetController,
        initialOffset: SheetOffset(initialSize),
        physics: sheetPhysics,
        snapGrid: snapGrid,
        scrollConfiguration: const SheetScrollConfiguration(
          scrollSyncMode: SheetScrollHandlingBehavior.onlyFromTop,
          delegateUnhandledOverscrollToChild: true,
        ),
        decoration: MaterialSheetDecoration(
          size: SheetSize.stretch,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          color: sheetColor,
          elevation: 4,
        ),
        // ──────────────────────────────────────────────────────────
        //  DIRECT child → SheetContentScaffold  (⭑ important! ⭑)
        // ──────────────────────────────────────────────────────────
        child: SheetContentScaffold(
          topBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header (drag handle + title) ──────────────────
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
                      appLoc.homePageJobsSheetTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // ── sort / search row ─────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // sort
                    Row(
                      children: [
                        Text(
                          appLoc.homePageSortByLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                            color: canInteract ? null : Colors.grey.shade400,
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: widget.sortBy,
                            focusColor: Colors.transparent,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 15,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'distance',
                                child: Text(appLoc.homePageSortByDistance),
                              ),
                              DropdownMenuItem(
                                value: 'pay',
                                child: Text(appLoc.homePageSortByPay),
                              ),
                            ],
                            onChanged: canInteract
                                ? (v) =>
                                    v != null ? widget.onSortChanged(v) : null
                                : null,
                          ),
                        ),
                      ],
                    ),
                    // search / refresh
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            widget.showSearchBar
                                ? Icons.search_off
                                : Icons.search,
                            color: canInteract
                                ? Colors.grey.shade600
                                : Colors.grey.shade400,
                          ),
                          tooltip: widget.showSearchBar
                              ? appLoc.homePageSearchCloseTooltip
                              : appLoc.homePageSearchOpenTooltip,
                          onPressed:
                              canInteract ? widget.toggleSearchBar : null,
                        ),
                        IconButton(
                          icon: widget.isLoadingJobs
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: widget.isOnline
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey.shade400,
                                  ),
                                )
                              : Icon(
                                  Icons.refresh,
                                  color: widget.isOnline
                                      ? Theme.of(context).primaryColor
                                      : Colors.grey.shade400,
                                ),
                          tooltip: appLoc.homePageJobsSheetRefreshTooltip,
                          onPressed: (widget.isOnline && !widget.isLoadingJobs)
                              ? () {
                                  logger.d('JobsSheet: Manual refresh.');
                                  ref
                                      .read(jobsNotifierProvider.notifier)
                                      .refreshOnlineJobsIfActive();
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // ── Animated search bar ──────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.fastOutSlowIn,
                child: widget.showSearchBar
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(
                          controller: widget.searchController,
                          focusNode: widget.searchFocusNode,
                          decoration: InputDecoration(
                            hintText: appLoc.homePageSearchHint,
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
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            suffixIcon: widget.searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
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
          body: bodyWidget,
        ),
      ),
    );
  }
}

