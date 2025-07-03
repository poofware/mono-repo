import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/core/providers/auth_controller_provider.dart';
import 'package:poof_worker/features/jobs/data/api/worker_jobs_api.dart';
import 'package:poof_worker/features/jobs/data/repositories/worker_jobs_repositories.dart';

/// A provider that builds a [WorkerJobsApi] instance for your jobs-service.
///
/// It injects the required [BaseTokenStorage], the [baseUrl] from
/// your flavor config, and an [onAuthLost] callback that triggers when
/// the API reports a 401 + failed refresh.
final workerJobsApiProvider = Provider<WorkerJobsApi>((ref) {
  final tokenStorage = ref.read(secureTokenStorageProvider);

  return WorkerJobsApi(
    tokenStorage: tokenStorage,
    onAuthLost: () => ref.read(authControllerProvider).handleAuthLost(),

  );
});

/// A provider that exposes the [WorkerJobsRepository] to the rest of the app.
/// The repository internally uses the [WorkerJobsApi] for all network requests.
final workerJobsRepositoryProvider = Provider<WorkerJobsRepository>((ref) {
  final jobsApi = ref.read(workerJobsApiProvider);
  return WorkerJobsRepository(jobsApi);
});

