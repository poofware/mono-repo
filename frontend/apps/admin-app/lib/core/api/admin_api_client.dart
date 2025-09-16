// frontend/apps/admin-app/lib/core/api/admin_api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:poof_admin/core/models/paginated_response.dart';
import 'package:poof_admin/features/account/data/api/admin_api_interface.dart';
import 'package:poof_admin/features/account/data/models/pm_models.dart';
import 'package:poof_admin/features/auth/data/api/admin_auth_api.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';

class AdminApiClient implements AdminApiInterface {
  final AdminAuthApi _authApi;
  // These are now path prefixes, not full base URLs.
  final String _accountPathPrefix = '/api/v1/account/admin';
  final String _jobsPathPrefix = '/api/v1/jobs/admin';

  AdminApiClient(this._authApi);

  T _decodeResponse<T>(
    http.Response response,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return fromJson(decoded);
  }

  /// Generic request handler for entities.
  Future<T> _request<T>(
    String method,
    String relativePath, // e.g., '/property-managers'
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? body,
    bool isJobsService = false,
  }) async {
    final pathPrefix = isJobsService ? _jobsPathPrefix : _accountPathPrefix;
    // Construct the full path from the gateway root.
    final String fullPath = '$pathPrefix$relativePath';

    // The underlying authApi will prepend the gateway base URL (e.g., https://domain.com)
    final response = await _authApi.sendAuthenticatedRequest(
      method: method,
      path: fullPath, // Pass the path relative to the gateway root.
      body: body != null ? JsonSerializableMap(body) : null,
    );
    return _decodeResponse(response, fromJson);
  }

  Future<List<T>> _requestList<T>(
    String method,
    String relativePath,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? body,
  }) async {
    final String fullPath = '$_accountPathPrefix$relativePath';
    final response = await _authApi.sendAuthenticatedRequest(
      method: method,
      path: fullPath,
      body: body != null ? JsonSerializableMap(body) : null,
    );
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .map((e) => fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Generic request handler for actions that return no body (e.g., DELETE).
  Future<void> _requestVoid(
    String method,
    String relativePath, {
    Map<String, dynamic>? body,
    bool isJobsService = false,
  }) async {
    final pathPrefix = isJobsService ? _jobsPathPrefix : _accountPathPrefix;
    final String fullPath = '$pathPrefix$relativePath';

    await _authApi.sendAuthenticatedRequest(
      method: method,
      path: fullPath,
      body: body != null ? JsonSerializableMap(body) : null,
    );
  }

  // --- Getters ---

  @override
  Future<PmsSnapshot> getSnapshot(Map<String, dynamic> data) async {
    return _request(
      'POST',
      '/property-manager/snapshot',
      PmsSnapshot.fromJson,
      body: data,
    );
  }

  @override
  Future<PaginatedResponse<PropertyManagerAdmin>> searchPropertyManagers(
      Map<String, dynamic> data) async {
    final String fullPath = '$_accountPathPrefix/property-managers/search';

    final response = await _authApi.sendAuthenticatedRequest(
      method: 'POST',
      path: fullPath,
      body: JsonSerializableMap(data),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (decoded['data'] as List)
        .map((item) =>
            PropertyManagerAdmin.fromJson(item as Map<String, dynamic>))
        .toList();
    return PaginatedResponse(
      items: items,
      totalCount: decoded['total'] as int,
      hasMore: (decoded['page'] as int) * (decoded['page_size'] as int) <
          (decoded['total'] as int),
    );
  }

  // --- Create Methods ---
  @override
  Future<PropertyManagerAdmin> createPropertyManager(
          Map<String, dynamic> data) =>
      _request('POST', '/property-managers', PropertyManagerAdmin.fromJson,
          body: data);

  @override
  Future<PropertyAdmin> createProperty(Map<String, dynamic> data) =>
      _request('POST', '/properties', PropertyAdmin.fromJson, body: data);

  @override
  Future<BuildingAdmin> createBuilding(Map<String, dynamic> data) =>
      _request('POST', '/property-buildings', BuildingAdmin.fromJson,
          body: data);

  @override
  Future<FloorAdmin> createFloor(Map<String, dynamic> data) =>
      _request('POST', '/floors', FloorAdmin.fromJson, body: data);

  @override
  Future<UnitAdmin> createUnit(Map<String, dynamic> data) =>
      _request('POST', '/units', UnitAdmin.fromJson, body: data);

  @override
  Future<void> createUnits(List<Map<String, dynamic>> data) {
    // Prefer backend batch endpoint for efficiency.
    return _authApi.sendAuthenticatedRequest(
      method: 'POST',
      path: '$_accountPathPrefix/units/batch',
      body: JsonSerializableMap({'items': data}),
    ).then((_) => null);
  }

  @override
  Future<DumpsterAdmin> createDumpster(Map<String, dynamic> data) =>
      _request('POST', '/dumpsters', DumpsterAdmin.fromJson, body: data);

  @override
  Future<JobDefinitionAdmin> createJobDefinition(Map<String, dynamic> data) =>
      _request('POST', '/job-definitions', JobDefinitionAdmin.fromJson,
          body: data, isJobsService: true);

  @override
  Future<AgentAdmin> createAgent(Map<String, dynamic> data) =>
      _request('POST', '/agents', AgentAdmin.fromJson, body: data);

  // --- Update Methods ---
  @override
  Future<PropertyManagerAdmin> updatePropertyManager(
          Map<String, dynamic> data) =>
      _request('PATCH', '/property-managers', PropertyManagerAdmin.fromJson,
          body: data);

  @override
  Future<PropertyAdmin> updateProperty(Map<String, dynamic> data) =>
      _request('PATCH', '/properties', PropertyAdmin.fromJson, body: data);

  @override
  Future<BuildingAdmin> updateBuilding(Map<String, dynamic> data) =>
      _request('PATCH', '/property-buildings', BuildingAdmin.fromJson,
          body: data);

  @override
  Future<UnitAdmin> updateUnit(Map<String, dynamic> data) =>
      _request('PATCH', '/units', UnitAdmin.fromJson, body: data);

  @override
  Future<DumpsterAdmin> updateDumpster(Map<String, dynamic> data) =>
      _request('PATCH', '/dumpsters', DumpsterAdmin.fromJson, body: data);

  @override
  Future<JobDefinitionAdmin> updateJobDefinition(Map<String, dynamic> data) =>
      _request('PATCH', '/job-definitions', JobDefinitionAdmin.fromJson,
          body: data, isJobsService: true);

  @override
  Future<AgentAdmin> updateAgent(Map<String, dynamic> data) =>
      _request('PATCH', '/agents', AgentAdmin.fromJson, body: data);

  // --- Delete Methods ---
  @override
  Future<void> deletePropertyManager(Map<String, dynamic> data) =>
      _requestVoid('DELETE', '/property-managers', body: data);

  @override
  Future<void> deleteProperty(Map<String, dynamic> data) =>
      _requestVoid('DELETE', '/properties', body: data);

  @override
  Future<void> deleteBuilding(Map<String, dynamic> data) =>
      _requestVoid('DELETE', '/property-buildings', body: data);

  @override
  Future<void> deleteUnit(Map<String, dynamic> data) =>
      _requestVoid('DELETE', '/units', body: data);

  @override
  Future<void> deleteDumpster(Map<String, dynamic> data) =>
      _requestVoid('DELETE', '/dumpsters', body: data);

  @override
  Future<void> deleteJobDefinition(Map<String, dynamic> data) =>
      _requestVoid('DELETE', '/job-definitions',
          body: data, isJobsService: true);

  @override
  Future<void> deleteAgent(Map<String, dynamic> data) =>
      _requestVoid('DELETE', '/agents', body: data);

  @override
  Future<List<FloorAdmin>> listFloorsByBuilding(Map<String, dynamic> data) async {
    return _requestList('POST', '/floors/by-building', FloorAdmin.fromJson, body: data);
  }
}

class JsonSerializableMap implements JsonSerializable {
  final Map<String, dynamic> _map;
  JsonSerializableMap(this._map);
  @override
  Map<String, dynamic> toJson() => _map;
}