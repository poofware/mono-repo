// worker-app/lib/features/earnings/state/earnings_state_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';

import '../data/repositories/earnings_repository.dart';
import '../data/models/dummy_earnings_data.dart';
import 'earnings_state.dart';

class EarningsNotifier extends StateNotifier<EarningsState> {
  final EarningsRepository _repository;
  final PoofWorkerFlavorConfig _flavor;
  final Ref _ref;

  EarningsNotifier(this._repository, this._flavor, this._ref) : super(const EarningsState());

  /// Fetches the earnings summary from the repository.
  ///
  /// By default, this method is idempotent: if earnings data already exists in the
  /// state, it will not re-fetch. To force a refresh (e.g., for pull-to-refresh
  /// or after completing a job), set [force] to `true`.
  Future<void> fetchEarningsSummary({bool force = false}) async {
    // Guard against concurrent fetches.
    if (state.isLoading) return;

    // If we have data and we are not forcing a refresh, skip.
    if (state.summary != null && !force) {
      _ref.read(appLoggerProvider).d('Earnings summary already exists and not forced. Skipping fetch.');
      return;
    }

    _ref.read(appLoggerProvider).d('Fetching earnings summary (force: $force)...');
    state = state.copyWith(isLoading: true, clearError: true);

    if (_flavor.testMode) {
      _ref.read(appLoggerProvider).d('Using dummy earnings data for test mode.');
      await Future.delayed(const Duration(milliseconds: 500));
      state = state.copyWith(
        isLoading: false,
        summary: DummyEarningsData.summary,
      );
      return;
    }

    try {
      final summary = await _repository.getEarningsSummary();
      state = state.copyWith(isLoading: false, summary: summary);
      _ref.read(appLoggerProvider).d('Successfully fetched earnings summary.');
    } catch (e) {
      _ref.read(appLoggerProvider).e('Failed to fetch earnings summary: $e');
      state = state.copyWith(
        isLoading: false,
        error: e,
      );
    }
  }

  /// Clears the error from the state. Called by the UI after displaying a SnackBar.
  void clearError() {
    if (state.error != null) {
      state = state.copyWith(clearError: true);
    }
  }
}
