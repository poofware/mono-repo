// frontend/apps/admin-app/lib/features/jobs/state/job_definition_form_notifier.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/data/api/api_exception.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/jobs/state/job_definition_form_state.dart';

class JobDefinitionFormNotifier extends StateNotifier<JobDefinitionFormState> {
  final Ref _ref;

  JobDefinitionFormNotifier(this._ref)
      : super(const JobDefinitionFormState.initial());

  Future<bool> createJobDefinition(
      String pmId, Map<String, dynamic> data) async {
    state = const JobDefinitionFormState.loading();
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      // The backend expects manager_id in the payload for creation
      final payload = {...data, 'manager_id': pmId};
      await repo.createJobDefinition(payload);
      _ref.invalidate(pmSnapshotProvider(pmId));
      state =
          const JobDefinitionFormState.success('Job Definition created successfully!');
      return true;
    } on ApiException catch (e) {
      state = JobDefinitionFormState.error(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = JobDefinitionFormState.error(e.toString());
      return false;
    }
  }

  Future<bool> updateJobDefinition(
      String jobDefinitionId, String pmId, Map<String, dynamic> data) async {
    state = const JobDefinitionFormState.loading();
    try {
      final repo = _ref.read(pmsRepositoryProvider);
      // The backend expects definition_id in the payload for updates
      final payload = {...data, 'definition_id': jobDefinitionId};
      await repo.updateJobDefinition(payload);
      _ref.invalidate(pmSnapshotProvider(pmId));
      state = const JobDefinitionFormState.success(
          'Job Definition updated successfully!');
      return true;
    } on ApiException catch (e) {
      state = JobDefinitionFormState.error(e.message, e.fieldErrors);
      return false;
    } catch (e) {
      state = JobDefinitionFormState.error(e.toString());
      return false;
    }
  }
}