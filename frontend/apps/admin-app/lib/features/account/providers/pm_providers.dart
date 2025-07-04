import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/data/api/mock_admin_pms_api.dart';
import 'package:poof_admin/features/account/data/models/pms_snapshot.dart';
import 'package:poof_admin/features/account/data/models/property_manager_admin.dart';
import 'package:poof_admin/features/account/data/repositories/admin_pm_repository.dart';
import 'package:poof_admin/features/account/state/pm_detail_notifier.dart';
import 'package:poof_admin/features/account/state/pm_detail_state.dart';
import 'package:poof_admin/features/account/state/property_form_notifier.dart';
import 'package:poof_admin/features/account/state/property_form_state.dart';

/// Provider for the (mock) API service. Singleton.
final pmsApiProvider = Provider<MockAdminPmsApi>((ref) {
  return MockAdminPmsApi();
});

/// Provider for the repository. Singleton.
final pmsRepositoryProvider = Provider<AdminPmsRepository>((ref) {
  return AdminPmsRepository(ref.read(pmsApiProvider));
});

/// Provider to fetch the list of all property managers.
final pmsListProvider = FutureProvider<List<PropertyManagerAdmin>>((ref) async {
  final query = ref.watch(pmsSearchQueryProvider);
  return ref.watch(pmsRepositoryProvider).searchPropertyManagers(query);
});

/// State provider to hold the current search query for the PM list.
final pmsSearchQueryProvider = StateProvider<String>((ref) => '');

/// A family provider to fetch the detailed snapshot for a specific PM.
final pmSnapshotProvider = FutureProvider.autoDispose.family<PmsSnapshot, String>((ref, pmId) {
  // By watching the detail provider, this will auto-refresh when actions
  // like deletion succeed.
  ref.watch(pmsDetailProvider);
  return ref.watch(pmsRepositoryProvider).getSnapshot(pmId);
});

/// Provider for the detail page's action controller (e.g., for deletions).
final pmsDetailProvider =
    StateNotifierProvider.autoDispose<PmDetailNotifier, PmDetailState>((ref) {
  return PmDetailNotifier(ref);
});

/// Provider for the Property form.
final propertyFormProvider =
    StateNotifierProvider.autoDispose<PropertyFormNotifier, PropertyFormState>((ref) {
  return PropertyFormNotifier(ref);
});