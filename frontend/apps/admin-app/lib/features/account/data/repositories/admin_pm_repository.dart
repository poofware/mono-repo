import 'package:poof_admin/features/account/data/api/mock_admin_pms_api.dart';
import 'package:poof_admin/features/account/data/models/pm_models.dart';

/// Repository for the admin property management feature.
/// Acts as a layer between the UI/state management and the data source (API).
class AdminPmsRepository {
  final MockAdminPmsApi _api;

  AdminPmsRepository(this._api);

  // --- Getters ---

  Future<PmsSnapshot> getSnapshot(String pmId) {
    return _api.getSnapshot(pmId);
  }

  Future<List<PropertyManagerAdmin>> searchPropertyManagers(String query) {
    return _api.searchPropertyManagers(query);
  }

  // --- Create Methods ---

  Future<PropertyManagerAdmin> createPropertyManager(Map<String, dynamic> data) {
    return _api.createPropertyManager(data);
  }

  Future<PropertyAdmin> createProperty(Map<String, dynamic> data) {
    return _api.createProperty(data);
  }

  Future<BuildingAdmin> createBuilding(Map<String, dynamic> data) {
    return _api.createBuilding(data);
  }

  Future<UnitAdmin> createUnit(Map<String, dynamic> data) {
    return _api.createUnit(data);
  }

  Future<DumpsterAdmin> createDumpster(Map<String, dynamic> data) {
    return _api.createDumpster(data);
  }

  Future<JobDefinitionAdmin> createJobDefinition(Map<String, dynamic> data) {
    return _api.createJobDefinition(data);
  }

  // --- Update Methods ---

  Future<PropertyManagerAdmin> updatePropertyManager(String pmId, Map<String, dynamic> data) {
    return _api.updatePropertyManager(pmId, data);
  }

  Future<PropertyAdmin> updateProperty(String propertyId, Map<String, dynamic> data) {
    return _api.updateProperty(propertyId, data);
  }

  Future<BuildingAdmin> updateBuilding(String buildingId, Map<String, dynamic> data) {
    return _api.updateBuilding(buildingId, data);
  }

  Future<UnitAdmin> updateUnit(String unitId, Map<String, dynamic> data) {
    return _api.updateUnit(unitId, data);
  }

  Future<DumpsterAdmin> updateDumpster(String dumpsterId, Map<String, dynamic> data) {
    return _api.updateDumpster(dumpsterId, data);
  }

  Future<JobDefinitionAdmin> updateJobDefinition(String jobDefinitionId, Map<String, dynamic> data) {
    return _api.updateJobDefinition(jobDefinitionId, data);
  }

  // --- Delete Methods ---

  Future<void> deletePropertyManager(String pmId) {
    return _api.deletePropertyManager(pmId);
  }

  Future<void> deleteProperty(String propertyId) {
    return _api.deleteProperty(propertyId);
  }

  Future<void> deleteBuilding(String buildingId) {
    return _api.deleteBuilding(buildingId);
  }

  Future<void> deleteUnit(String unitId) {
    return _api.deleteUnit(unitId);
  }

  Future<void> deleteDumpster(String dumpsterId) {
    return _api.deleteDumpster(dumpsterId);
  }

  Future<void> deleteJobDefinition(String jobDefinitionId) {
    return _api.deleteJobDefinition(jobDefinitionId);
  }
}