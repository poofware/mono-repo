// frontend/apps/admin-app/lib/features/account/data/models/property_admin.dart

import 'package:poof_admin/features/account/data/models/building_admin.dart';
import 'package:poof_admin/features/account/data/models/dumpster_admin.dart';
import 'package:poof_admin/features/jobs/data/models/job_definition_admin.dart';

class PropertyAdmin {
  final String id;
  final String managerId;
  final String propertyName;
  final String address;
  final String city;
  final String state;
  final String zipCode;
  final String timeZone;
  final double latitude;
  final double longitude;
  final List<BuildingAdmin> buildings;
  final List<DumpsterAdmin> dumpsters;
  final List<JobDefinitionAdmin> jobDefinitions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  PropertyAdmin({
    required this.id,
    required this.managerId,
    required this.propertyName,
    required this.address,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.timeZone,
    required this.latitude,
    required this.longitude,
    required this.buildings,
    required this.dumpsters,
    required this.jobDefinitions,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  PropertyAdmin.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        managerId = json['manager_id'] as String,
        propertyName = json['property_name'] as String,
        address = json['address'] as String,
        city = json['city'] as String,
        state = json['state'] as String,
        zipCode = json['zip_code'] as String,
        timeZone = json['timezone'] as String,
        latitude = json['latitude'] as double,
        longitude = json['longitude'] as double,
        buildings = (json['buildings'] as List<dynamic>?)
                ?.map((b) => BuildingAdmin.fromJson(b as Map<String, dynamic>))
                .toList() ??
            [],
        dumpsters = (json['dumpsters'] as List<dynamic>?)
                ?.map((d) => DumpsterAdmin.fromJson(d as Map<String, dynamic>))
                .toList() ??
            [],
        jobDefinitions = (json['job_definitions'] as List<dynamic>?)
                ?.map((j) => JobDefinitionAdmin.fromJson(j as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt = DateTime.parse(json['created_at'] as String),
        updatedAt = DateTime.parse(json['updated_at'] as String),
        deletedAt = json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String);

  PropertyAdmin copyWith({
    DateTime? deletedAt,
    List<BuildingAdmin>? buildings,
    List<DumpsterAdmin>? dumpsters,
    List<JobDefinitionAdmin>? jobDefinitions,
  }) =>
      PropertyAdmin(
        id: id,
        managerId: managerId,
        propertyName: propertyName,
        address: address,
        city: city,
        state: state,
        zipCode: zipCode,
        timeZone: timeZone,
        latitude: latitude,
        longitude: longitude,
        buildings: buildings ?? this.buildings,
        dumpsters: dumpsters ?? this.dumpsters,
        jobDefinitions: jobDefinitions ?? this.jobDefinitions,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'manager_id': managerId,
        'property_name': propertyName,
        'address': address,
        'city': city,
        'state': state,
        'zip_code': zipCode,
        'timezone': timeZone,
        'latitude': latitude,
        'longitude': longitude,
        'buildings': buildings.map((b) => b.toJson()).toList(),
        'dumpsters': dumpsters.map((d) => d.toJson()).toList(),
        'job_definitions': jobDefinitions.map((j) => j.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };
}