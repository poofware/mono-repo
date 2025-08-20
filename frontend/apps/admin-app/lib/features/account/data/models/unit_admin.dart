// NEW FILE
class UnitAdmin {
  final String id;
  final String propertyId;
  final String buildingId;
  final String unitNumber;
  final String tenantToken;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  UnitAdmin({
    required this.id,
    required this.propertyId,
    required this.buildingId,
    required this.unitNumber,
    required this.tenantToken,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  UnitAdmin.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        propertyId = json['property_id'] as String,
        buildingId = json['building_id'] as String,
        unitNumber = json['unit_number'] as String,
        tenantToken = json['tenant_token'] as String,
        createdAt = DateTime.parse(json['created_at'] as String),
        updatedAt = DateTime.parse(json['updated_at'] as String),
        deletedAt = json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String);

  UnitAdmin copyWith({DateTime? deletedAt}) {
    final json = toJson();
    if (deletedAt != null) {
      json['deleted_at'] = deletedAt.toIso8601String();
    }
    return UnitAdmin.fromJson(json);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'property_id': propertyId,
        'building_id': buildingId,
        'unit_number': unitNumber,
        'tenant_token': tenantToken,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };
}