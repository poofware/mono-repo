import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'job_history_state.dart'; // We can reuse the JobHistoryFilters class
import '../data/models/job_status.dart';

// This notifier ONLY manages the state of the filter UI controls.
class JobFiltersNotifier extends StateNotifier<JobHistoryFilters> {
  JobFiltersNotifier() : super(const JobHistoryFilters());

  void setDateRangePreset(DateRangePreset preset) {
    state = state.copyWith(
      dateRangePreset: preset,
      customStartDate: () => null,
      customEndDate: () => null,
    );
  }

  void setCustomDateRange(DateTime? start, DateTime? end) {
    state = state.copyWith(
      dateRangePreset: DateRangePreset.custom,
      customStartDate: () => start,
      customEndDate: () => end,
    );
  }

  void setJobStatusFilter(JobStatus? status) {
    state = state.copyWith(jobStatus: () => status);
  }
}