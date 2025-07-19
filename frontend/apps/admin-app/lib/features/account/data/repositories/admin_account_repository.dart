import 'package:poof_admin/core/models/paginated_response.dart';
import 'package:poof_admin/features/account/data/api/admin_api_interface.dart';
import 'package:poof_admin/features/account/data/models/pm_models.dart';

/// Repository for the admin account management feature.
/// Acts as a layer between the UI/state management and the data source (API).
class AdminAccountRepository {
  final AdminApiInterface _api;

  AdminAccountRepository(this._api);

  // --- Getters ---

  Future<PmsSnapshot> getSnapshot(Map<String, dynamic> data) {
    return _api.getSnapshot(data);
  }

  Future<PaginatedResponse<PropertyManagerAdmin>> searchPropertyManagers(
      Map<String, dynamic> data) {
    return _api.searchPropertyManagers(data);
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

  Future<void> createUnits(List<Map<String, dynamic>> data) {
    return _api.createUnits(data);
  }

  Future<DumpsterAdmin> createDumpster(Map<String, dynamic> data) {
    return _api.createDumpster(data);
  }

  // --- Update Methods ---

  Future<PropertyManagerAdmin> updatePropertyManager(Map<String, dynamic> data) {
    return _api.updatePropertyManager(data);
  }

  Future<PropertyAdmin> updateProperty(Map<String, dynamic> data) {
    return _api.updateProperty(data);
  }

  Future<BuildingAdmin> updateBuilding(Map<String, dynamic> data) {
    return _api.updateBuilding(data);
  }

  Future<UnitAdmin> updateUnit(Map<String, dynamic> data) {
    return _api.updateUnit(data);
  }

  Future<DumpsterAdmin> updateDumpster(Map<String, dynamic> data) {
    return _api.updateDumpster(data);
  }

  // --- Delete Methods ---

  Future<void> deletePropertyManager(Map<String, dynamic> data) {
    return _api.deletePropertyManager(data);
  }

  Future<void> deleteProperty(Map<String, dynamic> data) {
    return _api.deleteProperty(data);
  }

  Future<void> deleteBuilding(Map<String, dynamic> data) {
    return _api.deleteBuilding(data);
  }

  Future<void> deleteUnit(Map<String, dynamic> data) {
    return _api.deleteUnit(data);
  }

  Future<void> deleteDumpster(Map<String, dynamic> data) {
    return _api.deleteDumpster(data);
  }
}