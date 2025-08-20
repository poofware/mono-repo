// worker-app/lib/features/jobs/state/jobs_state.dart

import 'package:poof_worker/features/jobs/data/models/job_models.dart';

/// A simple immutable state class for the Jobs feature.
class JobsState {
  /// Whether the user is currently "online," i.e. searching for jobs.
  final bool isOnline;

  /// Whether we are currently fetching the list of available open jobs.
  final bool isLoadingOpenJobs;

  /// Whether we are currently fetching the user's accepted or in-progress jobs.
  final bool isLoadingAcceptedJobs;

  /// Whether the initial go-online fetch (open + accepted jobs) has fully completed.
  /// This controls when the jobs sheet refresh spinner switches from grey to the
  /// primary-colored version.
  final bool hasLoadedInitialJobs;

  /// The list of open jobs fetched from the server (or dummy data).
  final List<JobInstance> openJobs;

  /// The list of accepted (but not started) jobs.
  final List<JobInstance> acceptedJobs;

  /// A job that is currently in progress. If non-null, the user is locked into this job.
  final JobInstance? inProgressJob;

  /// If any error object occurred while fetching.
  final Object? error;

  const JobsState({
    this.isOnline = false,
    this.isLoadingOpenJobs = false,
    this.isLoadingAcceptedJobs = false,
    this.openJobs = const [],
    this.acceptedJobs = const [],
    this.inProgressJob,
    this.error,
    this.hasLoadedInitialJobs = false,
  });

  JobsState copyWith({
    bool? isOnline,
    bool? isLoadingOpenJobs,
    bool? isLoadingAcceptedJobs,
    bool? hasLoadedInitialJobs,
    List<JobInstance>? openJobs,
    List<JobInstance>? acceptedJobs,
    JobInstance? inProgressJob,
    bool clearInProgressJob = false,
    Object? error,
    bool clearError = false,
  }) {
    return JobsState(
      isOnline: isOnline ?? this.isOnline,
      isLoadingOpenJobs: isLoadingOpenJobs ?? this.isLoadingOpenJobs,
      isLoadingAcceptedJobs:
          isLoadingAcceptedJobs ?? this.isLoadingAcceptedJobs,
      hasLoadedInitialJobs: hasLoadedInitialJobs ?? this.hasLoadedInitialJobs,
      openJobs: openJobs ?? this.openJobs,
      acceptedJobs: acceptedJobs ?? this.acceptedJobs,
      inProgressJob: clearInProgressJob
          ? null
          : inProgressJob ?? this.inProgressJob,
      error: clearError ? null : error ?? this.error,
    );
  }
}
