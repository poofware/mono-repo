import '../api/worker_jobs_api.dart';
import '../models/job_models.dart';
import 'dart:io';

/// A repository that orchestrates the calls to [WorkerJobsApi]
/// and could integrate any additional caching or offline logic.
class WorkerJobsRepository {
  final WorkerJobsApi _api;

  WorkerJobsRepository(this._api);

  /// GET /api/v1/jobs/open
  Future<ListJobsResponse> listJobs({
    required double lat,
    required double lng,
    int page = 1,
    int size = 50,
  }) {
    return _api.listJobs(lat: lat, lng: lng, page: page, size: size);
  }

  /// NEW: GET /api/v1/jobs/my
  Future<ListJobsResponse> listMyJobs({
    required double lat,
    required double lng,
    int page = 1,
    int size = 50,
  }) {
    return _api.listMyJobs(lat: lat, lng: lng, page: page, size: size);
  }

  /// POST /api/v1/jobs/accept
  /// Now location-based.
  Future<JobInstance> acceptJob({
    required String instanceId,
    required double lat,
    required double lng,
    required double accuracy,
    required int timestamp,
    bool isMock = false,
  }) {
    return _api.acceptJob(
      instanceId: instanceId,
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp: timestamp,
      isMock: isMock,
    );
  }

  /// POST /api/v1/jobs/start
  Future<JobInstance> startJob({
    required String instanceId,
    required double lat,
    required double lng,
    double accuracy = 0,
    int? timestamp,
    bool isMock = false,
  }) {
    final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    return _api.startJob(
      instanceId: instanceId,
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp: ts,
      isMock: isMock,
    );
  }

  /// POST /api/v1/jobs/unaccept
  /// *** UPDATED *** → now sends simple JobActionRequest (instanceId only)
  /// and does not require attestation, aligning with backend.
  Future<JobInstance> unacceptJob(String instanceId) {
    // API method now only takes instanceId
    return _api.unacceptJob(instanceId);
  }

  /// POST /api/v1/jobs/verify-unit-photo
  Future<JobInstance> verifyPhoto({
    required String instanceId,
    required String unitId,
    required double lat,
    required double lng,
    double accuracy = 0,
    int? timestamp,
    bool isMock = false,
    required File photo,
    bool missingTrashCan = false,
  }) async {
    final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    return _api.verifyPhoto(
      instanceId: instanceId,
      unitId: unitId,
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp: ts,
      isMock: isMock,
      photo: photo,
      missingTrashCan: missingTrashCan,
    );
  }

  /// POST /api/v1/jobs/dump-bags
  Future<JobInstance> dumpBags({
    required String instanceId,
    required double lat,
    required double lng,
    double accuracy = 0,
    int? timestamp,
    bool isMock = false,
  }) async {
    final ts = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    return _api.dumpBags(
      instanceId: instanceId,
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp: ts,
      isMock: isMock,
    );
  }

  /// POST /api/v1/jobs/cancel
  Future<JobInstance> cancelJob(String instanceId) {
    return _api.cancelJob(instanceId);
  }
}
