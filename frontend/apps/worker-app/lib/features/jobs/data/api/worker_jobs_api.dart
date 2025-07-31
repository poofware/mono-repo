import 'dart:convert';
import 'dart:io';

import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/config/flavors.dart';
import '../models/job_models.dart';

const String _v1Jobs = '/v1/jobs';

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
      path: '$_v1Jobs/open$queryParams',
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
      path: '$_v1Jobs/my$queryParams',
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
      path: '$_v1Jobs/accept',
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
      path: '$_v1Jobs/start',
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
      path: '$_v1Jobs/unaccept',
      body: req,
      requireAttestation: false,
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final jar = JobInstanceActionResponse.fromJson(decoded);
    return jar.updated;
  }

  /// POST /jobs/verify-unit-photo (multipart)
  Future<JobInstance> verifyPhoto({
    required String instanceId,
    required String unitId,
    required double lat,
    required double lng,
    required double accuracy,
    required int timestamp,
    bool isMock = false,
    required File photo,
  }) async {
    final req = JobLocationActionRequest(
      instanceId: instanceId,
      lat: lat,
      lng: lng,
      accuracy: accuracy,
      timestamp: timestamp,
      isMock: isMock,
    );
    final fields = req.toFormFields();
    fields['unit_id'] = unitId;

    final resp = await sendAuthenticatedMultipartRequest(
      method: 'POST',
      path: '$_v1Jobs/verify-unit-photo',
      fields: fields,
      files: [photo],
      requireAttestation: true,
    );

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final jar = JobInstanceActionResponse.fromJson(decoded);
    return jar.updated;
  }

  /// POST /jobs/dump-bags
  Future<JobInstance> dumpBags({
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
      path: '$_v1Jobs/dump-bags',
      body: req,
      requireAttestation: true,
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final jar = JobInstanceActionResponse.fromJson(decoded);
    return jar.updated;
  }

  /// POST /jobs/cancel
  Future<JobInstance> cancelJob(String instanceId) async {
    final req = JobActionRequest(instanceId);
    final resp = await sendAuthenticatedRequest(
      method: 'POST',
      path: '$_v1Jobs/cancel',
      body: req,
      requireAttestation: false, // Or true if desired
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final jar = JobInstanceActionResponse.fromJson(decoded);
    return jar.updated;
  }
}

