// frontend/apps/admin-app/lib/features/jobs/data/repositories/admin_jobs_repository.dart

import 'package:poof_admin/features/account/data/api/admin_api_interface.dart';
import 'package:poof_admin/features/jobs/data/models/job_definition_admin.dart';

/// Repository for the admin jobs feature.
/// Acts as a layer between the UI/state management and the data source (API).
class AdminJobsRepository {
  final AdminApiInterface _api;

  AdminJobsRepository(this._api);

  Future<JobDefinitionAdmin> createJobDefinition(Map<String, dynamic> data) {
    return _api.createJobDefinition(data);
  }

  Future<JobDefinitionAdmin> updateJobDefinition(Map<String, dynamic> data) {
    return _api.updateJobDefinition(data);
  }

  Future<void> deleteJobDefinition(Map<String, dynamic> data) {
    return _api.deleteJobDefinition(data);
  }
}