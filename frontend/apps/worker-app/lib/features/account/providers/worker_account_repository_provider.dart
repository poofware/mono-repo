// lib/features/account/providers/worker_account_repository_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/api/worker_account_api.dart';
import '../data/repositories/worker_account_repository.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';
import 'package:poof_worker/core/providers/auth_controller_provider.dart';

// NEW import for the WorkerStateNotifier
import 'package:poof_worker/features/account/providers/providers.dart'
    show workerStateNotifierProvider;

final workerAccountApiProvider = Provider<WorkerAccountApi>((ref) {
  final tokenStorage = ref.read(secureTokenStorageProvider);

  return WorkerAccountApi(
    tokenStorage: tokenStorage,
    onAuthLost: () => ref.read(authControllerProvider).handleAuthLost(),
  );
});

/// The WorkerAccountRepository also needs the WorkerStateNotifier so that
/// we can update the worker data after getWorker() or patchWorker().
final workerAccountRepositoryProvider =
    Provider<WorkerAccountRepository>((ref) {
  final workerAccountApi = ref.read(workerAccountApiProvider);

  final workerNotifier = ref.read(workerStateNotifierProvider.notifier);

  return WorkerAccountRepository(
    workerAccountApi,
    workerNotifier,
  );
});

