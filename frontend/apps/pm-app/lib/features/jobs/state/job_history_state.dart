import 'package:flutter/foundation.dart';
import 'package:poof_pm/features/jobs/data/models/job_instance_pm.dart';
import '../data/models/job_status.dart';

enum DateRangePreset {
  last7days,
  last30days,
  last90days,
  thisYear,
  lastYear,
  custom,
}

@immutable
class JobHistoryFilters {
  final DateRangePreset dateRangePreset;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final JobStatus? jobStatus;

  const JobHistoryFilters({
    this.dateRangePreset = DateRangePreset.last7days,
    this.customStartDate,
    this.customEndDate,
    this.jobStatus,
  });

  /// Helper to compute the actual start and end dates based on the selected preset.
  ({DateTime? start, DateTime? end}) getDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    
    switch (dateRangePreset) {
      case DateRangePreset.last7days:
        return (start: today.subtract(const Duration(days: 6)), end: endOfToday);
      case DateRangePreset.last30days:
        return (start: today.subtract(const Duration(days: 29)), end: endOfToday);
      case DateRangePreset.last90days:
        return (start: today.subtract(const Duration(days: 89)), end: endOfToday);
      case DateRangePreset.thisYear:
        return (start: DateTime(today.year, 1, 1), end: endOfToday);
      case DateRangePreset.lastYear:
        final lastYear = today.year - 1;
        return (start: DateTime(lastYear, 1, 1), end: DateTime(lastYear, 12, 31, 23, 59, 59));
      case DateRangePreset.custom:
        final end = customEndDate != null
            ? DateTime(customEndDate!.year, customEndDate!.month, customEndDate!.day, 23, 59, 59)
            : null;
        return (start: customStartDate, end: end);
    }
  }

  JobHistoryFilters copyWith({
    DateRangePreset? dateRangePreset,
    ValueGetter<DateTime?>? customStartDate,
    ValueGetter<DateTime?>? customEndDate,
    ValueGetter<JobStatus?>? jobStatus,
  }) {
    return JobHistoryFilters(
      dateRangePreset: dateRangePreset ?? this.dateRangePreset,
      customStartDate: customStartDate != null ? customStartDate() : this.customStartDate,
      customEndDate: customEndDate != null ? customEndDate() : this.customEndDate,
      jobStatus: jobStatus != null ? jobStatus() : this.jobStatus,
    );
  }
}

@immutable
class JobHistoryState {
  final List<JobInstancePm> allEntries;
  final List<JobInstancePm> filteredEntries;
  final JobHistoryFilters filters;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalItems;

  const JobHistoryState({
    this.allEntries = const [],
    this.filteredEntries = const [],
    this.filters = const JobHistoryFilters(),
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalItems = 0,
  });

  JobHistoryState copyWith({
    List<JobInstancePm>? allEntries,
    List<JobInstancePm>? filteredEntries,
    JobHistoryFilters? filters,
    bool? isLoading,
    ValueGetter<String?>? error,
    int? currentPage,
    int? totalItems,
  }) {
    return JobHistoryState(
      allEntries: allEntries ?? this.allEntries,
      filteredEntries: filteredEntries ?? this.filteredEntries,
      filters: filters ?? this.filters,
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      currentPage: currentPage ?? this.currentPage,
      totalItems: totalItems ?? this.totalItems,
    );
  }
}