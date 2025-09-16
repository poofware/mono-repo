// frontend/apps/admin-app/lib/features/account/data/api/admin_api_interface.dart
import 'package:poof_admin/core/models/paginated_response.dart';
import 'package:poof_admin/features/account/data/models/pm_models.dart';

abstract class AdminApiInterface {
  // --- Search / Get ---
  Future<PaginatedResponse<PropertyManagerAdmin>> searchPropertyManagers(
      Map<String, dynamic> data);
  Future<PmsSnapshot> getSnapshot(Map<String, dynamic> data);
  Future<List<FloorAdmin>> listFloorsByBuilding(Map<String, dynamic> data);

  // --- Create Methods ---
  Future<PropertyManagerAdmin> createPropertyManager(Map<String, dynamic> data);
  Future<PropertyAdmin> createProperty(Map<String, dynamic> data);
  Future<BuildingAdmin> createBuilding(Map<String, dynamic> data);
  Future<FloorAdmin> createFloor(Map<String, dynamic> data);
  Future<UnitAdmin> createUnit(Map<String, dynamic> data);
  Future<void> createUnits(List<Map<String, dynamic>> data);
  Future<DumpsterAdmin> createDumpster(Map<String, dynamic> data);
  Future<JobDefinitionAdmin> createJobDefinition(Map<String, dynamic> data);
  Future<AgentAdmin> createAgent(Map<String, dynamic> data);

  // --- Update Methods ---
  Future<PropertyManagerAdmin> updatePropertyManager(Map<String, dynamic> data);
  Future<PropertyAdmin> updateProperty(Map<String, dynamic> data);
  Future<BuildingAdmin> updateBuilding(Map<String, dynamic> data);
  Future<UnitAdmin> updateUnit(Map<String, dynamic> data);
  Future<DumpsterAdmin> updateDumpster(Map<String, dynamic> data);
  Future<JobDefinitionAdmin> updateJobDefinition(Map<String, dynamic> data);
  Future<AgentAdmin> updateAgent(Map<String, dynamic> data);

  // --- Delete Methods ---
  Future<void> deletePropertyManager(Map<String, dynamic> data);
  Future<void> deleteProperty(Map<String, dynamic> data);
  Future<void> deleteBuilding(Map<String, dynamic> data);
  Future<void> deleteUnit(Map<String, dynamic> data);
  Future<void> deleteDumpster(Map<String, dynamic> data);
  Future<void> deleteJobDefinition(Map<String, dynamic> data);
  Future<void> deleteAgent(Map<String, dynamic> data);
}