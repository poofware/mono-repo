// worker-app/lib/features/jobs/presentation/pages/accepted_jobs_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/theme/app_constants.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/accepted_job_card_widget.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/accepted_job_details_sheet.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/date_carousel_widget.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

// --- Helper Functions ---

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

DateTime _parseServiceDate(String ymd) {
  final parts = ymd.split('-');
  if (parts.length != 3) return DateTime(1970);
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

// --- Sealed Class for UI State ---

sealed class AcceptedJobsDisplayState {
  const AcceptedJobsDisplayState();
}

class NoJobsAccepted extends AcceptedJobsDisplayState {
  const NoJobsAccepted();
}

class NoDateSelected extends AcceptedJobsDisplayState {
  const NoDateSelected();
}

class NoJobsForSelectedDate extends AcceptedJobsDisplayState {
  const NoJobsForSelectedDate();
}

class JobsAvailable extends AcceptedJobsDisplayState {
  final List<JobInstance> jobs;
  const JobsAvailable(this.jobs);
}

// --- Page Widget ---

class AcceptedJobsPage extends ConsumerStatefulWidget {
  const AcceptedJobsPage({super.key});

  @override
  ConsumerState<AcceptedJobsPage> createState() => _AcceptedJobsPageState();
}

class _AcceptedJobsPageState extends ConsumerState<AcceptedJobsPage>
    with AutomaticKeepAliveClientMixin {
  String _sortBy = 'time'; // MODIFIED: Default sort is now 'time'
  DateTime? _selectedDate;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Auto-select the first day with an accepted job upon initialization.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateSelectedDate();
      }
    });
  }
  
  void _updateSelectedDate() {
    // This function ensures the selected date is always valid or null.
    final accepted = ref.read(jobsNotifierProvider).acceptedJobs;

    // Case 1: No jobs exist. Clear any selection.
    if (accepted.isEmpty) {
      if (_selectedDate != null) {
        setState(() => _selectedDate = null);
      }
      return;
    }

    // Case 2: Jobs exist. Check if the current selection is valid.
    final uniqueJobDates =
        accepted.map((j) => _parseServiceDate(j.serviceDate)).toSet();
    final isCurrentDateValid = _selectedDate != null &&
        uniqueJobDates.any((d) => _isSameDate(d, _selectedDate!));

    // If the current selection is still valid, do nothing.
    if (isCurrentDateValid) {
      return;
    }

    // Case 3: Current selection is not valid (or is null). Select the first available date.
    final sortedDates = uniqueJobDates.toList()..sort();
    if (mounted) {
      setState(() => _selectedDate = sortedDates.first);
    }
  }


  /// The accepted jobs from the state
  List<JobInstance> get _acceptedJobs {
    final state = ref.watch(jobsNotifierProvider);
    return state.acceptedJobs;
  }

  /// Determines the current display state based on jobs and selection.
  AcceptedJobsDisplayState _getDisplayState() {
    if (_acceptedJobs.isEmpty) {
      return const NoJobsAccepted();
    }
    if (_selectedDate == null) {
      return const NoDateSelected();
    }

    final sameDayJobs = _acceptedJobs.where((job) {
      final jobDate = _parseServiceDate(job.serviceDate);
      return _isSameDate(jobDate, _selectedDate!);
    }).toList();

    if (sameDayJobs.isEmpty) {
      return const NoJobsForSelectedDate();
    }

    // MODIFIED: Sorting logic updated
    switch (_sortBy) {
      case 'distance':
        sameDayJobs.sort((a, b) => a.distanceMiles.compareTo(b.distanceMiles));
        break;
      case 'time':
        sameDayJobs.sort((a, b) {
          int timeComparison =
              a.workerStartTimeHint.compareTo(b.workerStartTimeHint);
          if (timeComparison != 0) {
            return timeComparison;
          }
          return a.distanceMiles.compareTo(b.distanceMiles);
        });
        break;
    }

    return JobsAvailable(sameDayJobs);
  }

  /// Calculates the dates to show in the carousel.
  /// The carousel starts from yesterday only if a job exists on that day.
  List<DateTime> _getCarouselDates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.add(const Duration(days: -1));
  
    // Check if any accepted job is from yesterday.
    final bool hasJobYesterday = _acceptedJobs
        .any((j) => _isSameDate(_parseServiceDate(j.serviceDate), yesterday));
  
    // The carousel starts from yesterday if there's a job on that day, otherwise today.
    final DateTime carouselStartDate = hasJobYesterday ? yesterday : today;
  
    // Default end date is 7 days from today.
    final defaultEndDate = today.add(const Duration(days: 7));
  
    if (_acceptedJobs.isEmpty) {
      // Show a default range from the determined start date.
      final dayCount = defaultEndDate.difference(carouselStartDate).inDays + 1;
      return List.generate(dayCount, (i) => carouselStartDate.add(Duration(days: i)));
    }
  
    // Find the latest job date to ensure the carousel extends far enough.
    final jobDates = _acceptedJobs.map((j) => _parseServiceDate(j.serviceDate));
    DateTime latestJobDate = today;
    for (final date in jobDates) {
      if (date.isAfter(latestJobDate)) latestJobDate = date;
    }
  
    final carouselEndDate =
        latestJobDate.isAfter(defaultEndDate) ? latestJobDate : defaultEndDate;
  
    // Calculate total days from the dynamic start date to the calculated end date.
    final dayCount = carouselEndDate.difference(carouselStartDate).inDays + 1;
  
    return List.generate(dayCount, (i) => carouselStartDate.add(Duration(days: i)));
  }

  void _handleDateSelected(DateTime day) {
    setState(() => _selectedDate = DateTime(day.year, day.month, day.day));
  }

  // MODIFIED: Sort toggle logic
  void _handleSortToggle(int index) {
    setState(() {
      _sortBy = (index == 0) ? 'time' : 'distance';
    });
  }

  void _showAcceptedJobSheet(BuildContext context, JobInstance job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        // By wrapping the sheet in its own Scaffold, ScaffoldMessenger.of(context)
        // inside the sheet will find this Scaffold first, and the SnackBar will
        // appear correctly on top of the sheet. We align the sheet to the bottom
        // to prevent it from filling the entire screen.
        return Scaffold(
          backgroundColor: Colors.transparent, // Keeps the modal transparent look
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AcceptedJobDetailsSheet(job: job),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final appLocalizations = AppLocalizations.of(context);

    // Watch the specific loading state for accepted jobs.
    final jobsState = ref.watch(jobsNotifierProvider);
    final isLoading = jobsState.isLoadingAcceptedJobs;
    final isOnline = jobsState.isOnline;

    // Listen for changes and update the selection reactively.
    ref.listen(
      jobsNotifierProvider.select((s) => s.acceptedJobs.length),
      (_, _) {
        // Using length is a simple way to detect add/remove.
        _updateSelectedDate();
      },
    );

    final carouselDates = _getCarouselDates();
    final uniqueJobDates =
        _acceptedJobs.map((j) => _parseServiceDate(j.serviceDate)).toSet();
    final displayState = _getDisplayState();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
              child: Text(
                appLocalizations.acceptedJobsTitle,
                style: const TextStyle(
                  fontSize: AppConstants.largeTitle,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                appLocalizations.acceptedJobsSubtitle,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color.fromARGB(255, 76, 76, 76),
                ),
              ),
            ),
            // The day carousel
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: DateCarousel(
                leftPadding: 12.0,
                availableDates: carouselDates,
                selectedDate: _selectedDate ?? DateTime(0),
                onDateSelected: _handleDateSelected,
                isDayEnabled: (day) {
                  return uniqueJobDates.any((jobDate) => _isSameDate(jobDate, day));
                },
              ),
            ),
            // Sorting and Refresh Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    appLocalizations.acceptedJobsSortByLabel,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  // MODIFIED: Toggle buttons updated
                  ToggleButtons(
                    isSelected: [
                      _sortBy == 'time',
                      _sortBy == 'distance',
                    ],
                    onPressed: _handleSortToggle,
                    constraints: const BoxConstraints(minHeight: 36, minWidth: 88),
                    borderRadius: BorderRadius.circular(8),
                    borderWidth: 1.5,
                    color: Colors.black87,
                    borderColor: Colors.grey.shade400,
                    selectedColor: Colors.black,
                    selectedBorderColor: Colors.grey.shade400,
                    fillColor: Colors.grey.shade300,
                    splashColor: Colors.grey.shade200,
                    highlightColor: Colors.grey.shade100,
                    hoverColor: Colors.grey.shade50,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(appLocalizations.acceptedJobsSortByTime),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(appLocalizations.homePageSortByDistance),
                      ),
                    ],
                  ),
                  const Spacer(), // Pushes the refresh button to the end
                  IconButton(
                    icon: SizedBox(
                      width: 28,
                      height: 28,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: isLoading
                            ? const Padding(
                                key: ValueKey('loader'),
                                padding: EdgeInsets.all(2.0),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3.0,
                                ),
                              )
                            : const Icon(
                                Icons.refresh,
                                key: ValueKey('icon'),
                                size: 28,
                              ),
                      ),
                    ),
                    onPressed: isLoading
                        ? null
                        : () {
                            if (isOnline) {
                              ref
                                  .read(jobsNotifierProvider.notifier)
                                  .refreshOnlineJobsIfActive();
                            } else {
                              ref
                                  .read(jobsNotifierProvider.notifier)
                                  .fetchAllMyJobs();
                            }
                          },
                    color: Theme.of(context).primaryColor,
                    tooltip: appLocalizations.homePageJobsSheetRefreshTooltip,
                  ),
                ],
              ),
            ),
            // Display Area
            Expanded(
              child: switch (displayState) {
                NoJobsAccepted() => _buildEmptyState(
                    context,
                    appLocalizations,
                    message: appLocalizations.acceptedJobsNoJobsAtAll,
                    showBrowseButton: true,
                  ),
                NoDateSelected() => _buildEmptyState(
                    context,
                    appLocalizations,
                    message: appLocalizations.acceptedJobsSelectADay,
                  ),
                NoJobsForSelectedDate() => _buildEmptyState(
                    context,
                    appLocalizations,
                    message: appLocalizations.acceptedJobsNoJobsForDay,
                    showBrowseButton: true,
                  ),
                JobsAvailable(jobs: final jobs) => ListView.builder(
                    itemCount: jobs.length,
                    itemBuilder: (context, index) {
                      final job = jobs[index];
                      return GestureDetector(
                        onTap: () => _showAcceptedJobSheet(context, job),
                        child: AcceptedJobCard(job: job),
                      );
                    },
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    AppLocalizations appLocalizations, {
    required String message,
    bool showBrowseButton = false,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy,
            size: 128,
            color: AppColors.poofColor.withAlpha(140),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(fontSize: 24),
            textAlign: TextAlign.center,
          ),
          if (showBrowseButton) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.poofColor,
                side: const BorderSide(color: AppColors.poofColor),
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 24,
                ),
                textStyle: const TextStyle(fontSize: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => DefaultTabController.of(context).animateTo(0),
              icon: const Icon(Icons.search),
              label: Text(appLocalizations.acceptedJobsBrowseJobsButton),
            ),
          ],
        ],
      ),
    );
  }
}
