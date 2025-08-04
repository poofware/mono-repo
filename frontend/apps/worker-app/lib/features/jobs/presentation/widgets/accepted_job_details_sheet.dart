// worker-app/lib/features/jobs/presentation/widgets/accepted_job_details_sheet.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/features/jobs/presentation/pages/job_map_page.dart';
import 'package:poof_worker/features/jobs/presentation/pages/job_in_progress_page.dart'; // Import the page
import 'info_widgets.dart';

class AcceptedJobDetailsSheet extends ConsumerStatefulWidget {
  final JobInstance job;

  const AcceptedJobDetailsSheet({
    super.key,
    required this.job,
  });

  // ─── Manual static caches ────────────────────────────────────────────
  static final mapPages = <String, JobMapPage>{};
  static final entries = <String, OverlayEntry>{};
  static final _evictTimers = <String, Timer>{};
  static final _warmCompleters = <String, Completer<void>>{};

  @override
  ConsumerState<AcceptedJobDetailsSheet> createState() =>
      _AcceptedJobDetailsSheetState();
}

class _AcceptedJobDetailsSheetState
    extends ConsumerState<AcceptedJobDetailsSheet> {
  bool _isExpanded = false;
  bool _isUnaccepting = false;
  bool _isShowingMap = false;
  bool _isWarming = false;
  bool _isStartingJob = false;

  /// A getter to simplify checking if any async operation is in progress.
  bool get _isProcessing => _isStartingJob || _isUnaccepting;

  @override
  void initState() {
    super.initState();
    final id = widget.job.instanceId;
    AcceptedJobDetailsSheet._evictTimers[id]?.cancel();
    AcceptedJobDetailsSheet._evictTimers.remove(id);
  }

  @override
  void dispose() {
    final id = widget.job.instanceId;
    AcceptedJobDetailsSheet._evictTimers[id]?.cancel();
    AcceptedJobDetailsSheet._evictTimers[id] = Timer(
      const Duration(seconds: 30),
      () {
        final entry = AcceptedJobDetailsSheet.entries[id];
        if (entry != null && entry.mounted) entry.remove();
        AcceptedJobDetailsSheet.mapPages.remove(id);
        AcceptedJobDetailsSheet.entries.remove(id);
        AcceptedJobDetailsSheet._evictTimers.remove(id);
        AcceptedJobDetailsSheet._warmCompleters.remove(id);
      },
    );
    super.dispose();
  }

  Future<JobMapPage> _getOrWarmMap() async {
    final id = widget.job.instanceId;
    if (AcceptedJobDetailsSheet.mapPages.containsKey(id)) {
      final existingCompleter = AcceptedJobDetailsSheet._warmCompleters[id];
      if (existingCompleter != null) await existingCompleter.future;
      return AcceptedJobDetailsSheet.mapPages[id]!;
    }
    final completer = Completer<void>();
    AcceptedJobDetailsSheet._warmCompleters[id] = completer;
    final page = JobMapPage(
      key: GlobalObjectKey('map-$id'),
      job: widget.job,
      isForWarmup: true,
      buildAsScaffold: false, // MODIFIED: Always build without a scaffold.
      onReady: () {
        if (!completer.isCompleted) completer.complete();
        AcceptedJobDetailsSheet._warmCompleters.remove(id);
      },
    );
    final entry = OverlayEntry(
      maintainState: true,
      builder: (_) => Offstage(child: page),
    );
    Overlay.of(context).insert(entry);
    await completer.future;
    AcceptedJobDetailsSheet.mapPages[id] = page;
    AcceptedJobDetailsSheet.entries[id] = entry;
    return page;
  }

  Future<void> _handleViewJobMap() async {
    if (_isShowingMap) return;
    setState(() {
      _isShowingMap = true;
      _isWarming = true;
    });
    final mapPage = await _getOrWarmMap();
    if (!mounted) return;
    setState(() => _isWarming = false);
    final id = widget.job.instanceId;
    final oldEntry = AcceptedJobDetailsSheet.entries[id];
    if (oldEntry != null && oldEntry.mounted) oldEntry.remove();
    AcceptedJobDetailsSheet.entries.remove(id);
    final popupRoute = CachedMapPopupRoute(mapPage: mapPage, instanceId: id);
    await Navigator.of(context).push(popupRoute);
    await popupRoute.completed;
    if (!mounted) return;
    setState(() => _isShowingMap = false);
  }

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
      final warmedMap = await _getOrWarmMap();
      if (!mounted) {
        setState(() => _isStartingJob = false);
        return;
      }

      final pageToPush = JobInProgressPage(
        job: updatedJob,
        preWarmedMap: warmedMap,
      );

      final id = widget.job.instanceId;
      final oldMapEntry = AcceptedJobDetailsSheet.entries[id];
      if (oldMapEntry != null && oldMapEntry.mounted) {
        oldMapEntry.remove();
        AcceptedJobDetailsSheet.entries.remove(id);
      }

      final completer = Completer<void>();
      final entry = OverlayEntry(
        builder: (_) => Offstage(child: pageToPush),
      );
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Please wait for the operation to complete."),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.only(top: 12.0),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Padding(
            padding:
                EdgeInsets.fromLTRB(24, 0, 24, mediaQueryPadding.bottom + 16),
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
                Text(
                  widget.job.property.propertyName,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.job.property.address,
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                  textAlign: TextAlign.center,
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _infoItem(
                      icon: Icons.attach_money,
                      label: appLocalizations.acceptedJobsBottomSheetPayLabel,
                      value: '\$${widget.job.pay.toStringAsFixed(0)}',
                    ),
                    _infoItem(
                      icon: Icons.location_on,
                      label:
                          appLocalizations.acceptedJobsBottomSheetDistanceLabel,
                      value: widget.job.distanceLabel,
                    ),
                    _infoItem(
                      icon: Icons.timer,
                      label:
                          appLocalizations.acceptedJobsBottomSheetEstTimeLabel,
                      value: widget.job.displayTime,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  icon: Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 28),
                  label: Text(_isExpanded
                      ? appLocalizations.acceptedJobsBottomSheetHideDetails
                      : appLocalizations.acceptedJobsBottomSheetViewDetails),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.primaryColor,
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                    splashFactory: NoSplash.splashFactory,
                  ).copyWith(
                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild:
                      const SizedBox(width: double.infinity, height: 0),
                  secondChild:
                      _buildExpandedDetails(context, appLocalizations, theme),
                  crossFadeState: _isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),
                const SizedBox(height: 12),
                _buildActionButtons(appLocalizations),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedDetails(BuildContext context,
      AppLocalizations appLocalizations, ThemeData theme) {
    final formattedStartTime = formatTime(context, widget.job.startTimeHint);
    final formattedWindowStart =
        formatTime(context, widget.job.workerServiceWindowStart);
    final formattedWindowEnd =
        formatTime(context, widget.job.workerServiceWindowEnd);

    return Column(
      children: [
        const Divider(height: 1),
        const SizedBox(height: 16),
        _detailRow(
          icon: Icons.apartment_outlined,
          label: appLocalizations.jobAcceptSheetBuildings,
          value:
              '${widget.job.numberOfBuildings} bldg${widget.job.numberOfBuildings == 1 ? "" : "s"}',
        ),
        _detailRow(
          icon: Icons.stairs_outlined,
          label: appLocalizations.jobAcceptSheetFloors,
          value: widget.job.floorsLabel,
        ),
        _detailRow(
          icon: Icons.home_outlined,
          label: appLocalizations.jobAcceptSheetUnits,
          value: widget.job.totalUnitsLabel,
        ),
        _detailRow(
          icon: Icons.access_time_outlined,
          label: appLocalizations.jobAcceptSheetRecommendedStart,
          value: formattedStartTime,
        ),
        _detailRow(
          icon: Icons.hourglass_empty_outlined,
          label: appLocalizations.jobAcceptSheetServiceWindow,
          value: '$formattedWindowStart - $formattedWindowEnd',
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isWarming ? null : _handleViewJobMap,
            icon: const Icon(Icons.map_outlined),
            label: Text(_isWarming
                ? 'Preparing map…'
                : appLocalizations.acceptedJobsBottomSheetViewJobMap),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primaryColor,
              side: BorderSide(color: theme.primaryColor.withAlpha(127)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
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
            ),
            icon: _isStartingJob
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
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
            ),
            icon: _isUnaccepting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black54))
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

  Widget _infoItem(
      {required IconData icon, required String label, required String value}) {
    return Column(
      children: [
        Icon(icon, size: 28, color: Colors.black87),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _detailRow(
      {required IconData icon, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 20),
          const SizedBox(width: 16),
          Text(label,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade800)),
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
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    // MODIFIED: Wrap the map page in a Stack to add our own back button.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _inRoute,
            builder: (_, show,_) => show ? mapPage : const SizedBox.shrink(),
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
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    animation.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && !_reparented) {
        _inRoute.value = false;
        final entry = OverlayEntry(
          maintainState: true,
          builder: (_) => Offstage(child: mapPage),
        );
        Overlay.of(context).insert(entry);
        AcceptedJobDetailsSheet.entries[instanceId] = entry;
        _reparented = true;
      }
    });
    final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);
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
    return SlideTransition(
      position: tween.animate(curved),
      child: child,
    );
  }
}
