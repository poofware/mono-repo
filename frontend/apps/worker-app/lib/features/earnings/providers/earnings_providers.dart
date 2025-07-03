// lib/features/earnings/providers/earnings_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/providers/auth_controller_provider.dart';
import 'package:poof_worker/features/auth/providers/providers.dart';

import '../data/api/earnings_api.dart';
import '../data/repositories/earnings_repository.dart';
import '../state/earnings_state.dart';
import '../state/earnings_state_notifier.dart';

final earningsApiProvider = Provider<EarningsApi>((ref) {
  final tokenStorage = ref.read(secureTokenStorageProvider);
  return EarningsApi(
    tokenStorage: tokenStorage,
    onAuthLost: () => ref.read(authControllerProvider).handleAuthLost(),
  );
});

final earningsRepositoryProvider = Provider<EarningsRepository>((ref) {
  final api = ref.read(earningsApiProvider);
  return EarningsRepository(api);
});

final earningsNotifierProvider =
    StateNotifierProvider<EarningsNotifier, EarningsState>((ref) {
  final repo = ref.read(earningsRepositoryProvider);
  final flavor = PoofWorkerFlavorConfig.instance;
  return EarningsNotifier(repo, flavor, ref);
});
