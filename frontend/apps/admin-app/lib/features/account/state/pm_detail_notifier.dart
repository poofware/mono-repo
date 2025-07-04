import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/pm_detail_state.dart';

class PmDetailNotifier extends StateNotifier<PmDetailState> {
  final Ref _ref;

  PmDetailNotifier(this._ref) : super(const PmDetailState.initial());

  Future<bool> deletePm(String pmId) async {
    state = const PmDetailState.loading('Deleting Property Manager...');
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.deletePropertyManager(pmId);

      _ref.invalidate(pmsListProvider);
      _ref.invalidate(pmSnapshotProvider(pmId));

      state = const PmDetailState.success('Property Manager deleted.');
      return true;
    } catch (e) {
      state = PmDetailState.error(e.toString());
      return false;
    }
  }

  Future<bool> deleteProperty(String propertyId, String pmId) async {
    state = const PmDetailState.loading('Deleting Property...');
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.deleteProperty(propertyId);

      _ref.invalidate(pmSnapshotProvider(pmId)); // Refresh the detail view

      state = const PmDetailState.success('Property deleted.');
      return true;
    } catch (e) {
      state = PmDetailState.error(e.toString());
      return false;
    }
  }
}

final pmsDetailProvider =
    StateNotifierProvider<PmDetailNotifier, PmDetailState>((ref) {
  return PmDetailNotifier(ref);
});