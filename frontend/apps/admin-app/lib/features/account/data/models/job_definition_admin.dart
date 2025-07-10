// frontend/apps/admin-app/lib/features/account/data/models/job_definition_admin.dart

class JobDefinitionAdmin {
  final String id;
  final String managerId;
  final String propertyId;
  final String title;
  final String scheduleType;
  final int jobWindowMinutes;
  final double payRate;
  final List<String> buildingIds;
  final List<String> dumpsterIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  JobDefinitionAdmin({
    required this.id,
    required this.managerId,
    required this.propertyId,
    required this.title,
    required this.scheduleType,
    required this.jobWindowMinutes,
    required this.payRate,
    this.buildingIds = const [],
    this.dumpsterIds = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  JobDefinitionAdmin.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        managerId = json['manager_id'] as String,
        propertyId = json['property_id'] as String,
        title = json['title'] as String,
        scheduleType = json['schedule_type'] as String,
        jobWindowMinutes = json['job_window_minutes'] as int,
        payRate = (json['pay_rate'] as num).toDouble(),
        buildingIds = (json['building_ids'] as List<dynamic>?)
                ?.map((id) => id as String)
                .toList() ??
            [],
        dumpsterIds = (json['dumpster_ids'] as List<dynamic>?)
                ?.map((id) => id as String)
                .toList() ??
            [],
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
        'schedule_type': scheduleType,
        'job_window_minutes': jobWindowMinutes,
        'pay_rate': payRate,
        'building_ids': buildingIds,
        'dumpster_ids': dumpsterIds,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };
}