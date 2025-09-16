class FloorAdmin {
  final String id;
  final String propertyId;
  final String buildingId;
  final int number;
  final DateTime createdAt;
  final DateTime updatedAt;

  FloorAdmin({
    required this.id,
    required this.propertyId,
    required this.buildingId,
    required this.number,
    required this.createdAt,
    required this.updatedAt,
  });

  FloorAdmin.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        propertyId = json['property_id'] as String,
        buildingId = json['building_id'] as String,
        number = (json['number'] as num).toInt(),
        createdAt = DateTime.parse(json['created_at'] as String),
        updatedAt = DateTime.parse(json['updated_at'] as String);

  Map<String, dynamic> toJson() => {
        'id': id,
        'property_id': propertyId,
        'building_id': buildingId,
        'number': number,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}


