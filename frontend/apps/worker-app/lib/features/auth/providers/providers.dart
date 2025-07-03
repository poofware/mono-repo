// lib/features/auth/providers/auth_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/providers/auth_controller_provider.dart';
import '../data/api/worker_auth_api.dart';
import '../data/repositories/worker_auth_repository.dart';
import '../state/state.dart';

// NEW import for WorkerStateNotifier
import 'package:poof_worker/features/account/providers/providers.dart'
    show workerStateNotifierProvider;

/// Provider for secure token storage, specifically for Worker auth.
final secureTokenStorageProvider = Provider<SecureTokenStorage>((ref) {
  return SecureTokenStorage();
});

/// Provider for WorkerAuthApi, injecting the secure token storage.
/// We now supply onAuthLost → calls the AuthController to handle forced logout.
final workerAuthApiProvider = Provider<WorkerAuthApi>((ref) {
  final tokenStorage = ref.read(secureTokenStorageProvider);

  return WorkerAuthApi(
    tokenStorage: tokenStorage,
    onAuthLost: () => ref.read(authControllerProvider).handleAuthLost(),
  );
});

/// Provider for WorkerAuthRepository, injecting the Auth API, token storage,
/// and the WorkerStateNotifier so we can keep the Worker data updated after login.
final workerAuthRepositoryProvider = Provider<WorkerAuthRepository>((ref) {
  final authApi = ref.read(workerAuthApiProvider);
  final tokenStorage = ref.read(secureTokenStorageProvider);

  final workerNotifier = ref.read(workerStateNotifierProvider.notifier);

  return WorkerAuthRepository(
    authApi: authApi,
    tokenStorage: tokenStorage,
    workerNotifier: workerNotifier,
  );
});

/// The provider that pages/widgets can read/write for signup state.
final signUpProvider = StateNotifierProvider<SignUpStateNotifier, SignUpState>(
  (ref) => SignUpStateNotifier(),
);

