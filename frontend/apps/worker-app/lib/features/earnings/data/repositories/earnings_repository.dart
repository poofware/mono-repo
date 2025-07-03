// lib/features/earnings/data/repositories/earnings_repository.dart

import '../api/earnings_api.dart';
import '../models/earnings_models.dart';

class EarningsRepository {
  final EarningsApi _api;

  EarningsRepository(this._api);

  Future<EarningsSummary> getEarningsSummary() {
    return _api.getEarningsSummary();
  }
}
