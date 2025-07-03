// lib/features/earnings/state/earnings_state.dart

import '../data/models/earnings_models.dart';

class EarningsState {
  final bool isLoading;
  final Object? error;
  final EarningsSummary? summary;

  const EarningsState({
    this.isLoading = false,
    this.error,
    this.summary,
  });

  EarningsState copyWith({
    bool? isLoading,
    Object? error,
    EarningsSummary? summary,
    bool clearError = false,
  }) {
    return EarningsState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      summary: summary ?? this.summary,
    );
  }
}
