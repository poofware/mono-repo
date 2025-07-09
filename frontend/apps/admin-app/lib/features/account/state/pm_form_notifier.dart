import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/data/api/api_exception.dart';
import 'package:poof_admin/features/account/data/models/property_manager_admin.dart';
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

      // The list page will refresh automatically via its PagingController
      // when the user navigates back.
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
      final payload = {'id': pmId, ...data};
      await repo.updatePropertyManager(payload);

      // Invalidate detail provider to refresh it.
      // The list page will handle its own refresh.
      _ref.invalidate(pmSnapshotProvider(pmId));

      state = const PmFormState.success('Property Manager updated successfully!');
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 409 && e.entity is PropertyManagerAdmin) {
        state = PmFormState.conflict(
          e.entity as PropertyManagerAdmin,
          e.message,
        );
      } else if (e.statusCode == 409) {
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