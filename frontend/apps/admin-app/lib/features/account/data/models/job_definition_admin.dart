// NEW FILE
class JobDefinitionAdmin {
  final String id;
  final String managerId;
  final String propertyId;
  final String title;
  // Simplified for this context. A real implementation would have all fields.
  final String frequency;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  JobDefinitionAdmin({
    required this.id,
    required this.managerId,
    required this.propertyId,
    required this.title,
    required this.frequency,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  JobDefinitionAdmin.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        managerId = json['manager_id'] as String,
        propertyId = json['property_id'] as String,
        title = json['title'] as String,
        frequency = json['frequency'] as String,
        createdAt = DateTime.parse(json['created_at'] as String),
        updatedAt = DateTime.parse(json['updated_at'] as String),
        deletedAt = json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String);

  JobDefinitionAdmin copyWith({DateTime? deletedAt}) {
    final json = toJson();
    if (deletedAt != null) {
      json['deleted_at'] = deletedAt.toIso8601String();
    }
    return JobDefinitionAdmin.fromJson(json);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'manager_id': managerId,
        'property_id': propertyId,
        'title': title,
        'frequency': frequency,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };
}