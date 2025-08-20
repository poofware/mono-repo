// NEW FILE
import 'package:poof_admin/features/account/data/models/property_admin.dart';
import 'package:poof_admin/features/account/data/models/property_manager_admin.dart';

/// Represents the entire data hierarchy for a single Property Manager.
class PmsSnapshot {
  final PropertyManagerAdmin propertyManager;
  final List<PropertyAdmin> properties;

  PmsSnapshot({
    required this.propertyManager,
    required this.properties,
  });

  PmsSnapshot.fromJson(Map<String, dynamic> json)
      : propertyManager = PropertyManagerAdmin.fromJson(
            json['property_manager'] as Map<String, dynamic>),
        properties = (json['properties'] as List<dynamic>)
            .map((p) => PropertyAdmin.fromJson(p as Map<String, dynamic>))
            .toList();
  
   PmsSnapshot copyWith({
    PropertyManagerAdmin? propertyManager,
    List<PropertyAdmin>? properties,
  }) =>
      PmsSnapshot(
        propertyManager: propertyManager ?? this.propertyManager,
        properties: properties ?? this.properties,
      );

  Map<String, dynamic> toJson() => {
        'property_manager': propertyManager.toJson(),
        'properties': properties.map((p) => p.toJson()).toList(),
      };
}