import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/data/api/api_exception.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/property_form_state.dart';

class PropertyFormNotifier extends StateNotifier<PropertyFormState> {
  final Ref _ref;

  PropertyFormNotifier(this._ref) : super(const PropertyFormState.initial());

  Future<bool> createProperty(Map<String, dynamic> data) async {
    state = const PropertyFormState.loading();
    try {
      final repo = _ref.read(adminAccountRepositoryProvider);
      final pmId = data['manager_id'] as String;

      await repo.createProperty(data);

      _ref.invalidate(pmSnapshotProvider(pmId)); // Refresh the detail view
      state = const PropertyFormState.success('Property created successfully!');
      return true;
    } on ApiException catch (e) {
      state = PropertyFormState.error(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = PropertyFormState.error(e.toString());
      return false;
    }
  }

  Future<bool> updateProperty(
      String propertyId, Map<String, dynamic> data) async {
    state = const PropertyFormState.loading();
    try {
      final repo = _ref.read(adminAccountRepositoryProvider);
      final pmId = data['manager_id'] as String;
      final payload = {'id': propertyId, ...data};

      await repo.updateProperty(payload);

      _ref.invalidate(pmSnapshotProvider(pmId)); // Refresh the detail view

      state = const PropertyFormState.success('Property updated successfully!');
      return true;
    } on ApiException catch (e) {
      state = PropertyFormState.error(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = PropertyFormState.error(e.toString());
      return false;
    }
  }
}