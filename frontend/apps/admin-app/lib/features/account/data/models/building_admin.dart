// NEW FILE
import 'package:poof_admin/features/account/data/models/unit_admin.dart';
import 'package:poof_admin/features/account/data/models/floor_admin.dart';

class BuildingAdmin {
  final String id;
  final String propertyId;
  final String buildingName;
  final String? address;
  final double? latitude;
  final double? longitude;
  final List<FloorAdmin> floors;
  final List<UnitAdmin> units;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  BuildingAdmin({
    required this.id,
    required this.propertyId,
    required this.buildingName,
    this.address,
    this.latitude,
    this.longitude,
    required this.floors,
    required this.units,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  BuildingAdmin.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        propertyId = json['property_id'] as String,
        buildingName = json['building_name'] as String,
        address = json['address'] as String?,
        latitude = json['latitude'] as double?,
        longitude = json['longitude'] as double?,
        floors = (json['floors'] as List<dynamic>?)
                ?.map((f) => FloorAdmin.fromJson(f as Map<String, dynamic>))
                .toList() ??
            [],
        units = (json['units'] as List<dynamic>?)
                ?.map((u) => UnitAdmin.fromJson(u as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt = DateTime.parse(json['created_at'] as String),
        updatedAt = DateTime.parse(json['updated_at'] as String),
        deletedAt = json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String);

  BuildingAdmin deepCopy() => BuildingAdmin.fromJson(toJson());

  BuildingAdmin copyWith({DateTime? deletedAt}) {
    final json = toJson();
    if (deletedAt != null) {
      json['deleted_at'] = deletedAt.toIso8601String();
    }
    // This creates a new instance from the potentially modified JSON map
    return BuildingAdmin.fromJson(json);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'property_id': propertyId,
        'building_name': buildingName,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'floors': floors.map((f) => f.toJson()).toList(),
        'units': units.map((u) => u.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };
}