// NEW FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/data/api/api_exception.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/unit_form_state.dart';

class UnitFormNotifier extends StateNotifier<UnitFormState> {
  final Ref _ref;

  UnitFormNotifier(this._ref) : super(const UnitFormState.initial());

  Future<bool> createUnit(String pmId, Map<String, dynamic> data) async {
    state = const UnitFormState.loading();
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.createUnit(data);
      _ref.invalidate(pmSnapshotProvider(pmId));
      state = const UnitFormState.success('Unit created successfully!');
      return true;
    } on ApiException catch (e) {
      state = UnitFormState.error(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = UnitFormState.error(e.toString());
      return false;
    }
  }

  Future<bool> updateUnit(
      String unitId, String pmId, Map<String, dynamic> data) async {
    state = const UnitFormState.loading();
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.updateUnit(unitId, data);
      _ref.invalidate(pmSnapshotProvider(pmId));
      state = const UnitFormState.success('Unit updated successfully!');
      return true;
    } on ApiException catch (e) {
      state = UnitFormState.error(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = UnitFormState.error(e.toString());
      return false;
    }
  }
}