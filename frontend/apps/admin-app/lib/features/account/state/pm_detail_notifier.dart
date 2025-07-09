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
      await repo.deletePropertyManager({'id': pmId});

      // The list page (PmsDashboardPage) will refresh via its own mechanisms.
      // We still invalidate the snapshot provider in case the user tries to
      // access it again, ensuring they see the deleted state.
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
      await repo.deleteProperty({'id': propertyId});

      _ref.invalidate(pmSnapshotProvider(pmId)); // Refresh the detail view

      state = const PmDetailState.success('Property deleted.');
      return true;
    } catch (e) {
      state = PmDetailState.error(e.toString());
      return false;
    }
  }

  Future<bool> deleteBuilding(String buildingId, String pmId) async {
    state = const PmDetailState.loading('Deleting Building...');
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.deleteBuilding({'id': buildingId});
      _ref.invalidate(pmSnapshotProvider(pmId));
      state = const PmDetailState.success('Building deleted.');
      return true;
    } catch (e) {
      state = PmDetailState.error(e.toString());
      return false;
    }
  }

  Future<bool> deleteUnit(String unitId, String pmId) async {
    state = const PmDetailState.loading('Deleting Unit...');
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.deleteUnit({'id': unitId});
      _ref.invalidate(pmSnapshotProvider(pmId));
      state = const PmDetailState.success('Unit deleted.');
      return true;
    } catch (e) {
      state = PmDetailState.error(e.toString());
      return false;
    }
  }

  Future<bool> deleteDumpster(String dumpsterId, String pmId) async {
    state = const PmDetailState.loading('Deleting Dumpster...');
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.deleteDumpster({'id': dumpsterId});
      _ref.invalidate(pmSnapshotProvider(pmId));
      state = const PmDetailState.success('Dumpster deleted.');
      return true;
    } catch (e) {
      state = PmDetailState.error(e.toString());
      return false;
    }
  }

  Future<bool> deleteJobDefinition(String jobDefinitionId, String pmId) async {
    state = const PmDetailState.loading('Deleting Job Definition...');
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.deleteJobDefinition({'id': jobDefinitionId});
      _ref.invalidate(pmSnapshotProvider(pmId));
      state = const PmDetailState.success('Job Definition deleted.');
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