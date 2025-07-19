// frontend/apps/admin-app/lib/core/api/admin_api_client.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:poof_admin/core/config/flavors.dart';
import 'package:poof_admin/core/models/paginated_response.dart';
import 'package:poof_admin/features/account/data/api/admin_api_interface.dart';
import 'package:poof_admin/features/account/data/models/pm_models.dart';
import 'package:poof_admin/features/auth/data/api/admin_auth_api.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';

class AdminApiClient implements AdminApiInterface {
  final AdminAuthApi _authApi;
  final String _accountBaseUrl;
  final String _jobsBaseUrl;

  AdminApiClient(this._authApi)
      : _accountBaseUrl =
            '${PoofAdminFlavorConfig.instance.apiServiceURL}/account/admin',
        _jobsBaseUrl =
            '${PoofAdminFlavorConfig.instance.apiServiceURL}/jobs/admin';

  /// Helper to handle the response, decode JSON, and wrap potential errors.
  /// The underlying `sendAuthenticatedRequest` from poof_flutter_auth already handles
  /// token refresh and throws a structured `ApiException`, so we just need to decode the success case.
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
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? body,
    bool isJobsService = false,
  }) async {
    final baseUrl = isJobsService ? _jobsBaseUrl : _accountBaseUrl;
    final response = await _authApi.sendAuthenticatedRequest(
      method: method,
      path: '$baseUrl$path',
      body: body != null ? JsonSerializableMap(body) : null,
    );
    return _decodeResponse(response, fromJson);
  }

  /// Generic request handler for actions that return no body (e.g., DELETE).
  Future<void> _requestVoid(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool isJobsService = false,
  }) async {
    final baseUrl = isJobsService ? _jobsBaseUrl : _accountBaseUrl;
    await _authApi.sendAuthenticatedRequest(
      method: method,
      path: '$baseUrl$path',
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
    final response = await _authApi.sendAuthenticatedRequest(
      method: 'POST',
      path: '$_accountBaseUrl/property-managers/search',
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
  Future<UnitAdmin> createUnit(Map<String, dynamic> data) =>
      _request('POST', '/units', UnitAdmin.fromJson, body: data);

  @override
  Future<void> createUnits(List<Map<String, dynamic>> data) {
    // A real-world application should have a dedicated bulk endpoint.
    // Since one is not available based on the provided backend code,
    // we fall back to creating units individually.
    return Future.wait(data.map((unitData) => createUnit(unitData)));
  }

  @override
  Future<DumpsterAdmin> createDumpster(Map<String, dynamic> data) =>
      _request('POST', '/dumpsters', DumpsterAdmin.fromJson, body: data);

  @override
  Future<JobDefinitionAdmin> createJobDefinition(Map<String, dynamic> data) =>
      _request('POST', '/job-definitions', JobDefinitionAdmin.fromJson,
          body: data, isJobsService: true);

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
}

/// A helper class to wrap a map in the JsonSerializable interface required
/// by the poof_flutter_auth package's request handler.
class JsonSerializableMap implements JsonSerializable {
  final Map<String, dynamic> _map;
  JsonSerializableMap(this._map);
  @override
  Map<String, dynamic> toJson() => _map;
}