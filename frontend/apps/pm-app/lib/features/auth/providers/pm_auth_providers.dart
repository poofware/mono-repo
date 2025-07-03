import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/core/providers/app_providers.dart';

import '../data/api/pm_auth_api.dart';
import '../data/repositories/pm_auth_repository.dart';
import '../state/pm_sign_up_state.dart';
import '../state/pm_sign_up_state_notifier.dart';
import '../state/pm_user_state_notifier.dart';

/// 1) NoOpTokenStorage for PM
final pmNoOpTokenStorageProvider = Provider<BaseTokenStorage>((ref) {
  // If you want separate keys from worker, do so:
  return NoOpTokenStorage();
});

/// 2) The PM Auth API
final pmAuthApiProvider = Provider<PmAuthApi>((ref) {
  final tokenStorage = ref.read(pmNoOpTokenStorageProvider);

  return PmAuthApi(
    tokenStorage: tokenStorage,
    // If you want real attestation or dummy, pull from flavor config:
    useRealAttestation: PoofPMFlavorConfig.instance.testMode == false,
    onAuthLost: () => ref.read(authControllerProvider).handleAuthLost(),
  );
});

/// 3) A StateNotifier that holds the current PM user
final pmUserStateNotifierProvider =
    StateNotifierProvider<PmUserStateNotifier, PmUserState>(
  (_) => PmUserStateNotifier(),
);

/// 4) The PM Auth Repository
final pmAuthRepositoryProvider = Provider<PmAuthRepository>((ref) {
  final api = ref.read(pmAuthApiProvider);
  final tokenStorage = ref.read(pmNoOpTokenStorageProvider);
  final pmUserNotifier = ref.read(pmUserStateNotifierProvider.notifier);

  return PmAuthRepository(
    authApi: api,
    tokenStorage: tokenStorage,
    pmUserNotifier: pmUserNotifier,
  );
});

/// 5) The sign-up state to store partial data
final pmSignUpStateNotifierProvider =
    StateNotifierProvider<PmSignUpStateNotifier, PmSignUpState>(
  (_) => PmSignUpStateNotifier(),
);

