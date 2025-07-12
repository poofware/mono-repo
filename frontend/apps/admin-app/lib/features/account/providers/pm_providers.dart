import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/data/api/mock_admin_pms_api.dart';
import 'package:poof_admin/features/account/data/models/pms_snapshot.dart';
import 'package:poof_admin/features/account/data/repositories/admin_pm_repository.dart';
import 'package:poof_admin/features/account/state/building_form_notifier.dart';
import 'package:poof_admin/features/account/state/building_form_state.dart';
import 'package:poof_admin/features/account/state/dumpster_form_notifier.dart';
import 'package:poof_admin/features/account/state/dumpster_form_state.dart';
import 'package:poof_admin/features/account/state/job_definition_form_notifier.dart';
import 'package:poof_admin/features/account/state/job_definition_form_state.dart';
import 'package:poof_admin/features/account/state/pm_detail_notifier.dart';
import 'package:poof_admin/features/account/state/pm_detail_state.dart';
import 'package:poof_admin/features/account/state/property_form_notifier.dart';
import 'package:poof_admin/features/account/state/property_form_state.dart';
import 'package:poof_admin/features/account/state/unit_form_notifier.dart';
import 'package:poof_admin/features/account/state/unit_form_state.dart';

/// Provider for the (mock) API service. Singleton.
final pmsApiProvider = Provider<MockAdminPmsApi>((ref) {
  return MockAdminPmsApi();
});

/// Provider for the repository. Singleton.
final pmsRepositoryProvider = Provider<AdminPmsRepository>((ref) {
  return AdminPmsRepository(ref.read(pmsApiProvider));
});

/// State provider to hold the current search query for the PM list.
/// This is watched by the PmsDashboardPage to trigger a refresh on change.
final pmsSearchQueryProvider = StateProvider<String>((ref) => '');

/// A family provider to fetch the detailed snapshot for a specific PM.
final pmSnapshotProvider = FutureProvider.autoDispose.family<PmsSnapshot, String>((ref, pmId) {
  // This provider is responsible for fetching the data.
  // It is invalidated by notifiers (like pmsDetailProvider) when an action
  // (create, update, delete) completes, which correctly triggers a refresh.
  return ref.watch(pmsRepositoryProvider).getSnapshot({'manager_id': pmId});
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

/// Provider for the Building form.
final buildingFormProvider =
    StateNotifierProvider.autoDispose<BuildingFormNotifier, BuildingFormState>((ref) {
  return BuildingFormNotifier(ref);
});

/// Provider for the Unit form.
final unitFormProvider =
    StateNotifierProvider.autoDispose<UnitFormNotifier, UnitFormState>((ref) {
  return UnitFormNotifier(ref);
});

/// Provider for the Dumpster form.
final dumpsterFormProvider =
    StateNotifierProvider.autoDispose<DumpsterFormNotifier, DumpsterFormState>((ref) {
  return DumpsterFormNotifier(ref);
});

/// Provider for the JobDefinition form.
final jobDefinitionFormProvider =
    StateNotifierProvider.autoDispose<JobDefinitionFormNotifier, JobDefinitionFormState>((ref) {
  return JobDefinitionFormNotifier(ref);
});