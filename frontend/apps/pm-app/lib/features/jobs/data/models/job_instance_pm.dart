// You can adapt your existing JobHistoryEntry or create a new model.
// Let's create a new one for clarity.
import 'package:poof_pm/features/jobs/data/models/property_model_subset.dart';

import 'building_subset.dart';

class JobInstancePm {
  final String instanceId;
  final String definitionId;
  final String propertyId;
  final String serviceDate;
  final String status;
  final PropertySubset property;
  final List<BuildingSubset> buildings;
  // Add buildings if needed

  JobInstancePm({
    required this.instanceId,
    required this.definitionId,
    required this.propertyId,
    required this.serviceDate,
    required this.status,
    required this.property,
    required this.buildings,
  });

  factory JobInstancePm.fromJson(Map<String, dynamic> json) {
    var buildingsList = json['buildings'] as List? ?? [];
    List<BuildingSubset> buildings =
        buildingsList.map((i) => BuildingSubset.fromJson(i)).toList();

    return JobInstancePm(
      instanceId: json['instance_id'],
      definitionId: json['definition_id'],
      propertyId: json['property_id'],
      serviceDate: json['service_date'],
      status: json['status'],
      property: PropertySubset.fromJson(json['property']),
      buildings: buildings,
    );
  }
}