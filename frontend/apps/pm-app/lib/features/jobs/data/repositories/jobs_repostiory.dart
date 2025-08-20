import '../api/jobs_api.dart';
import '../models/job_instance_pm.dart';
import '../models/list_jobs_pm_request.dart';
import '../models/list_jobs_pm_response.dart';

class JobsRepository {
  final JobsApi _jobsApi;

  JobsRepository({required JobsApi jobsApi}) : _jobsApi = jobsApi;

  Future<List<JobInstancePm>> fetchJobsForProperty(String propertyId) async {
    final request = ListJobsPmRequest(propertyId: propertyId);
    final ListJobsPmResponse response = await _jobsApi.fetchJobsForProperty(request);
    return response.results;
  }
}