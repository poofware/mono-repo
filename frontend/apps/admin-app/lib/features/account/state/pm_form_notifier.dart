import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/data/api/api_exception.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/pm_form_state.dart';

class PmFormNotifier extends StateNotifier<PmFormState> {
  final Ref _ref;

  PmFormNotifier(this._ref) : super(const PmFormState.initial());

  Future<bool> createPm(Map<String, dynamic> data) async {
    state = const PmFormState.loading();
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.createPropertyManager(data);

      _ref.invalidate(pmsListProvider); // Refresh the list
      state = const PmFormState.success('Property Manager created successfully!');
      return true;
    } on ApiException catch (e) {
      state = PmFormState.error(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = PmFormState.error(e.toString());
      return false;
    }
  }

  Future<bool> updatePm(String pmId, Map<String, dynamic> data) async {
    state = const PmFormState.loading();
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      await repo.updatePropertyManager(pmId, data);

      // Invalidate both list and detail providers
      _ref.invalidate(pmsListProvider);
      _ref.invalidate(pmSnapshotProvider(pmId));

      state = const PmFormState.success('Property Manager updated successfully!');
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        state = PmFormState.error(
            'Conflict: This record was updated by someone else. Please refresh and try again.');
      } else {
        state = PmFormState.error(e.message, e.fieldErrors);
      }
      return false;
    } catch (e) {
      state = PmFormState.error(e.toString());
      return false;
    }
  }
}

final pmFormProvider =
    StateNotifierProvider.autoDispose<PmFormNotifier, PmFormState>((ref) {
  return PmFormNotifier(ref);
});