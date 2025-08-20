// NEW FILE
class DumpsterAdmin {
  final String id;
  final String propertyId;
  final String dumpsterNumber;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  DumpsterAdmin({
    required this.id,
    required this.propertyId,
    required this.dumpsterNumber,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  DumpsterAdmin.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        propertyId = json['property_id'] as String,
        dumpsterNumber = json['dumpster_number'] as String,
        latitude = json['latitude'] as double,
        longitude = json['longitude'] as double,
        createdAt = DateTime.parse(json['created_at'] as String),
        updatedAt = DateTime.parse(json['updated_at'] as String),
        deletedAt = json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String);

  DumpsterAdmin copyWith({DateTime? deletedAt}) {
    final json = toJson();
    if (deletedAt != null) {
      json['deleted_at'] = deletedAt.toIso8601String();
    }
    return DumpsterAdmin.fromJson(json);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'property_id': propertyId,
        'dumpster_number': dumpsterNumber,
        'latitude': latitude,
        'longitude': longitude,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };
}