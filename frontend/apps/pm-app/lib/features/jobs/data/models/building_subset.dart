import 'package:flutter/foundation.dart';

@immutable
class BuildingSubset {
  final String buildingId;
  final String name;
  final double latitude;
  final double longitude;

  const BuildingSubset({
    required this.buildingId,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  factory BuildingSubset.fromJson(Map<String, dynamic> json) {
    return BuildingSubset(
      buildingId: json['building_id'] as String? ?? '',
      name: json['building_name'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuildingSubset &&
          runtimeType == other.runtimeType &&
          buildingId == other.buildingId;

  @override
  int get hashCode => buildingId.hashCode;
}