import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/features/jobs/state/jobs_state.dart';
import 'package:poof_worker/features/jobs/providers/worker_jobs_repository_provider.dart';
import 'package:poof_worker/core/config/flavors.dart';

import '../state/jobs_state_notifier.dart';

/// A top-level provider for the JobsNotifier (the state machine for jobs).
final jobsNotifierProvider =
    StateNotifierProvider<JobsNotifier, JobsState>((ref) {
  final repo = ref.read(workerJobsRepositoryProvider);
  final flavor = PoofWorkerFlavorConfig.instance;
  return JobsNotifier(ref, repo, flavor);
});

