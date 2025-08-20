// lib/features/properties/data/models/property_model.dart
class Property {
  final String id;
  final String name;
  final String address;

  Property({
    required this.id,
    required this.name,
    required this.address,
  });

  // NEW: Add a fromJson factory constructor
  factory Property.fromJson(Map<String, dynamic> json) {
    return Property(
      id: json['id'] as String? ?? '',
      name: json['property_name'] as String? ?? 'Unnamed Property',
      address: json['address'] as String? ?? 'No Address',
    );
  }
}