import 'dart:async'; // Step 1: Import dart:async for Timer

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_pm/core/theme/app_colors.dart';
import 'package:poof_pm/core/theme/app_constants.dart';
import 'package:poof_pm/features/jobs/data/models/job_instance_pm.dart';
import 'package:poof_pm/features/jobs/data/models/job_status.dart';
import 'package:poof_pm/features/jobs/providers/job_providers.dart';
import 'package:poof_pm/features/jobs/presentation/widgets/job_history_filters_widget.dart';
import 'package:poof_pm/features/jobs/presentation/widgets/job_history_stats_card.dart';
import 'package:poof_pm/features/jobs/presentation/widgets/job_history_timeline.dart';
import 'package:poof_pm/features/jobs/state/job_history_state.dart';
import 'package:poof_pm/features/account/data/models/property_model.dart';
import 'package:poof_pm/features/account/providers/property_providers.dart';

class JobHistoryPage extends ConsumerStatefulWidget {
  const JobHistoryPage({super.key});

  @override
  ConsumerState<JobHistoryPage> createState() => _JobHistoryPageState();
}

class _JobHistoryPageState extends ConsumerState<JobHistoryPage> {
  Property? _selectedProperty;
  int _currentPage = 1;
  static const int _itemsPerPage = 10;

  // Step 2: Add state for the polling timer and define the interval.
  Timer? _pollingTimer;
  static const Duration _pollingInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    // Step 3: Start the polling when the widget is first created.
    _startPolling();
  }

  @override
  void dispose() {
    // Step 4: Cancel the timer when the widget is disposed to prevent memory leaks.
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// Starts a periodic timer to refresh the jobs data.
  void _startPolling() {
    // Cancel any existing timer to avoid duplicates.
    _pollingTimer?.cancel();

    // Start a new periodic timer.
    _pollingTimer = Timer.periodic(_pollingInterval, (_) {
      // Only refresh if a property is selected and the widget is still in the tree.
      if (_selectedProperty != null && mounted) {
        // Use ref.refresh to force a refetch of the provider.
        // This will update any widgets watching the provider and set `isRefreshing` to true.
        ref.refresh(jobsForPropertyProvider(_selectedProperty!.id));
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    // Watch the FutureProvider for properties.
    final propertiesAsync = ref.watch(propertiesProvider);

    // Use .when to handle the different states of the AsyncValue.
    return propertiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error loading properties: $err')),
      data: (properties) {
        // This block runs only when the properties have successfully loaded.
        
        // Handle initial selection once data is available.
        if (_selectedProperty == null && properties.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedProperty = properties.first;
              });
            }
          });
        }

        // If there are no properties, show a message.
        if (properties.isEmpty) {
          return const Center(child: Text("No properties found for this account."));
        }

        final jobsAsyncValue = _selectedProperty != null
            ? ref.watch(jobsForPropertyProvider(_selectedProperty!.id))
            : null;
        final filters = ref.watch(jobFiltersProvider);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.kDefaultHorizontalSpacing * 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppConstants.kDefaultVerticalSpacing, bottom: AppConstants.kDefaultVerticalSpacing),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedProperty?.name ?? 'No Property Selected',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_selectedProperty != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                _selectedProperty!.address,
                                style: Theme.of(context).textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Step 5: Add a visual indicator when data is being refreshed in the background.
                    if (jobsAsyncValue != null && jobsAsyncValue.isRefreshing)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2.0, color: AppColors.primary),
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (properties.length > 1)
                      DropdownButtonHideUnderline(
                        child: DropdownButton<Property>(
                          value: _selectedProperty,
                          icon: const Icon(Icons.unfold_more_rounded),
                          items: properties.map((Property property) {
                            return DropdownMenuItem<Property>(
                              value: property,
                              child: Text(property.name),
                            );
                          }).toList(),
                          onChanged: (Property? newValue) {
                            if (newValue != null && newValue.id != _selectedProperty?.id) {
                              setState(() {
                                _selectedProperty = newValue;
                                _currentPage = 1;
                              });
                              // No need to call invalidate. The `ref.watch` in the build method
                              // will automatically subscribe to the new provider with the new ID
                              // and trigger a fetch. The polling timer will also use the new ID
                              // on its next tick.
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const JobHistoryFiltersWidget(),
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppConstants.kDefaultVerticalSpacing),
                  // The `.when` will show a full-screen loader on initial load, but `isRefreshing`
                  // allows us to show a less intrusive indicator while displaying old data.
                  child: jobsAsyncValue?.when(
                        // `loading` is true for the initial fetch, but NOT for subsequent refreshes
                        // where we already have data.
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (err, stack) => Center(child: Text('Failed to load jobs: $err')),
                        data: (jobs) {
                          final filteredJobs = _applyFilters(jobs, filters);

                          if (filteredJobs.isEmpty) {
                            return const Center(child: Text('No jobs match the selected filters.'));
                          }

                          final totalItems = filteredJobs.length;
                          final totalPages = (totalItems / _itemsPerPage).ceil();
                          final startIndex = (_currentPage - 1) * _itemsPerPage;
                          final paginatedJobs = filteredJobs.sublist(
                              startIndex, (startIndex + _itemsPerPage > totalItems) ? totalItems : startIndex + _itemsPerPage);
                          
                          // Define a breakpoint for switching between desktop and mobile layouts.
                          const double kDesktopBreakpoint = 900.0;

                          return Column(
                            children: [
                              Expanded(
                                // MODIFICATION: Use LayoutBuilder to create an adaptive UI.
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    // WIDE SCREEN (Desktop) LAYOUT
                                    if (constraints.maxWidth > kDesktopBreakpoint) {
                                      return Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 4,
                                            child: JobHistoryStatsCard(entries: filteredJobs, filters: filters),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            flex: 6,
                                            child: Card(
                                              elevation: 1,
                                              shape: RoundedRectangleBorder(
                                                side: BorderSide(color: Colors.grey.shade200, width: 1),
                                                borderRadius: const BorderRadius.all(Radius.circular(12)),
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: JobHistoryTimeline(entries: paginatedJobs),
                                            ),
                                          ),
                                        ],
                                      );
                                    } 
                                    // NARROW SCREEN (Mobile) LAYOUT
                                    else {
                                      return SingleChildScrollView( // Make the content scrollable.
                                        child: Column(
                                          children: [
                                            // On mobile, constrain the stats card's height
                                            // to prevent it from taking too much vertical space.
                                            SizedBox(
                                              height: 500, 
                                              child: JobHistoryStatsCard(entries: filteredJobs, filters: filters),
                                            ),
                                            const SizedBox(height: 16),
                                            Card(
                                              elevation: 1,
                                              shape: RoundedRectangleBorder(
                                                side: BorderSide(color: Colors.grey.shade200, width: 1),
                                                borderRadius: const BorderRadius.all(Radius.circular(12)),
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              // Give the timeline a height to prevent layout errors inside SingleChildScrollView
                                              child: SizedBox(
                                                height: 500,
                                                child: JobHistoryTimeline(entries: paginatedJobs)
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                              if (totalPages > 1)
                                _buildPaginationControls(totalPages),
                            ],
                          );
                        },
                      ) ?? const Center(child: Text('Please select a property.')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<JobInstancePm> _applyFilters(List<JobInstancePm> jobs, JobHistoryFilters filters) {
    return jobs.where((job) {
      if (filters.jobStatus != null && jobStatusFromString(job.status) != filters.jobStatus) {
        return false;
      }
      final jobDate = DateTime.parse(job.serviceDate);
      final dateRange = filters.getDateRange();
      if (dateRange.start != null && jobDate.isBefore(dateRange.start!)) {
        return false;
      }
      if (dateRange.end != null && jobDate.isAfter(dateRange.end!)) {
        return false;
      }
      return true;
    }).toList();
  }

  Widget _buildPaginationControls(int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: AppConstants.kDefaultHorizontalSpacing),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Page $_currentPage of $totalPages',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.chevron_left, size: 20),
                label: const Text('Prev'),
                onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  disabledForegroundColor: Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Text('Next'),
                label: const Icon(Icons.chevron_right, size: 20),
                onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  disabledForegroundColor: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}