// NEW FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/data/api/api_exception.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/building_form_state.dart';

class BuildingFormNotifier extends StateNotifier<BuildingFormState> {
  final Ref _ref;

  BuildingFormNotifier(this._ref) : super(const BuildingFormState.initial());

  Future<bool> createBuilding(String pmId, Map<String, dynamic> data) async {
    state = const BuildingFormState.loading();
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.createBuilding(data);
      _ref.invalidate(pmSnapshotProvider(pmId));
      state = const BuildingFormState.success('Building created successfully!');
      return true;
    } on ApiException catch (e) {
      state = BuildingFormState.error(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = BuildingFormState.error(e.toString());
      return false;
    }
  }

  Future<bool> updateBuilding(
      String buildingId, String pmId, Map<String, dynamic> data) async {
    state = const BuildingFormState.loading();
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      final payload = {'id': buildingId, ...data};
      await repo.updateBuilding(payload);
      _ref.invalidate(pmSnapshotProvider(pmId));
      state = const BuildingFormState.success('Building updated successfully!');
      return true;
    } on ApiException catch (e) {
      state = BuildingFormState.error(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = BuildingFormState.error(e.toString());
      return false;
    }
  }
}