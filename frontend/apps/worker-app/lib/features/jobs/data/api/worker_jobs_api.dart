import 'dart:convert';
import 'dart:io';

import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/config/flavors.dart';
import '../models/job_models.dart';

/// A specialized API client for the "jobs-service" endpoints relevant to workers.
///
/// We use [AuthenticatedApiMixin] for normal JSON endpoints (list, accept, start, unaccept).
/// For "complete job", we need a special multipart request with photos.
class WorkerJobsApi with AuthenticatedApiMixin {
  @override
  final BaseTokenStorage tokenStorage;

  @override
  final void Function()? onAuthLost;

  /// Typically your main API URL for the "job-service".
  @override
  String get baseUrl => PoofWorkerFlavorConfig.instance.apiServiceURL;

  /// For refreshing tokens. We can share the same auth server path or a dedicated route.
  @override
  String get refreshTokenBaseUrl => PoofWorkerFlavorConfig.instance.authServiceURL;

  @override
  String get refreshTokenPath => '/worker/refresh_token';

  @override
  String get attestationChallengeBaseUrl => PoofWorkerFlavorConfig.instance.authServiceURL;

  @override
  String get attestationChallengePath => '/worker/challenge';

  @override
  final bool useRealAttestation;

  WorkerJobsApi({
    required this.tokenStorage,
    this.onAuthLost,
  }) : useRealAttestation =
      PoofWorkerFlavorConfig.instance.realDeviceAttestation;

  /// GET /jobs/open?lat=&lng=&page=&size=
  Future<ListJobsResponse> listJobs({
    required double lat,
    required double lng,
    int page = 1,
    int size = 50,
  }) async {
    final queryParams = '?lat=$lat&lng=$lng&page=$page&size=$size';
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/jobs/open$queryParams',
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    return ListJobsResponse.fromJson(decoded);
  }

  /// NEW: GET /jobs/my?lat=&lng=&page=&size=
  ///
  /// Returns the worker’s assigned or in-progress jobs, sorted by distance
  /// but *not filtered* by distance.
  Future<ListJobsResponse> listMyJobs({
    required double lat,
    required double lng,
    int page = 1,
    int size = 50,
  }) async {
    final queryParams = '?lat=$lat&lng=$lng&page=$page&size=$size';
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/jobs/my$queryParams',
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    return ListJobsResponse.fromJson(decoded);
  }

  /// POST /jobs/accept
  /// Now uses JobLocationActionRequest for location-based accept.
  Future<JobInstance> acceptJob({
    required String instanceId,
    required double lat,
    required double lng,
    required double accuracy,
    required int timestamp,
    bool isMock = false,
  }) async {
    final req = JobLocationActionRequest(
      instanceId: instanceId,
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp: timestamp,
      isMock: isMock,
    );

    final resp = await sendAuthenticatedRequest(
      method: 'POST',
      path: '/jobs/accept',
      body: req,
      requireAttestation: true,
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final jar = JobInstanceActionResponse.fromJson(decoded);
    return jar.updated;
  }

  /// POST /jobs/start
  /// Must include lat/lng/timestamp, also with device attestation.
  Future<JobInstance> startJob({
    required String instanceId,
    required double lat,
    required double lng,
    required double accuracy,
    required int timestamp,
    bool isMock = false,
  }) async {
    final req = JobLocationActionRequest(
      instanceId: instanceId,
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp: timestamp,
      isMock: isMock,
    );

    final resp = await sendAuthenticatedRequest(
      method: 'POST',
      path: '/jobs/start',
      body: req,
      requireAttestation: true,
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final jar = JobInstanceActionResponse.fromJson(decoded);
    return jar.updated;
  }

  /// POST /jobs/unaccept
  /// aligning with current backend.
  Future<JobInstance> unacceptJob(String instanceId) async {
    final req = JobActionRequest(instanceId);

    final resp = await sendAuthenticatedRequest(
      method: 'POST',
      path: '/jobs/unaccept',
      body: req,
      requireAttestation: false,
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final jar = JobInstanceActionResponse.fromJson(decoded);
    return jar.updated;
  }

  /// POST /jobs/complete (multipart form-data)
  ///
  /// `photos` is optional. If empty, no files are attached, but the server might reject
  /// if the job requires proof photos. `lat` and `lng` must be included as form fields.
  Future<JobInstance> completeJob({
    required String instanceId,
    required double lat,
    required double lng,
    required double accuracy,
    required int timestamp,
    bool isMock = false,
    List<File> photos = const [],
  }) async {
    // 1) prepare fields:
    final req = JobLocationActionRequest(
      instanceId: instanceId,
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp: timestamp,
      isMock: isMock,
    );
    final fields = req.toFormFields();

    // 2) call new sendAuthenticatedMultipartRequest
    final resp = await sendAuthenticatedMultipartRequest(
      method: 'POST',
      path: '/jobs/complete',
      fields: fields,
      files: photos, // We rely on IoAuthStrategy for actual file uploading
      requireAttestation: true,
    );

    // 3) parse success
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final jar = JobInstanceActionResponse.fromJson(decoded);
    return jar.updated;
  }

  /// POST /jobs/cancel
  Future<JobInstance> cancelJob(String instanceId) async {
    final req = JobActionRequest(instanceId);
    final resp = await sendAuthenticatedRequest(
      method: 'POST',
      path: '/jobs/cancel',
      body: req,
      requireAttestation: false, // Or true if desired
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final jar = JobInstanceActionResponse.fromJson(decoded);
    return jar.updated;
  }
}

