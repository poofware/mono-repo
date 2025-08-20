// frontend/apps/admin-app/lib/features/jobs/data/models/job_definition_admin.dart
import 'package:flutter/material.dart';

class JobDefinitionAdmin {
  final String id;
  final String managerId;
  final String propertyId;
  final String title;
  final String? description;
  final List<String> assignedBuildingIds;
  final List<String> dumpsterIds;
  final String frequency;
  final List<int> weekdays;
  final int? intervalWeeks;
  final DateTime startDate;
  final DateTime? endDate;
  final TimeOfDay earliestStartTime;
  final TimeOfDay latestStartTime;
  final TimeOfDay? startTimeHint;
  final bool skipHolidays;
  final JobCompletionRulesAdmin? completionRules;
  final List<DailyPayEstimateAdmin> dailyPayEstimates;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  JobDefinitionAdmin({
    required this.id,
    required this.managerId,
    required this.propertyId,
    required this.title,
    this.description,
    this.assignedBuildingIds = const [],
    this.dumpsterIds = const [],
    required this.frequency,
    this.weekdays = const [],
    this.intervalWeeks,
    required this.startDate,
    this.endDate,
    required this.earliestStartTime,
    required this.latestStartTime,
    this.startTimeHint,
    required this.skipHolidays,
    this.completionRules,
    this.dailyPayEstimates = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  static TimeOfDay _timeFromJson(String timeStr) {
    final parsed = DateTime.parse(timeStr);
    return TimeOfDay.fromDateTime(parsed.toLocal());
  }

  static String? _timeToJson(TimeOfDay? time) {
    if (time == null) return null;
    final now = DateTime.now();
    // Use a dummy date to create a DateTime object, then convert to UTC ISO 8601 string
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return dt.toUtc().toIso8601String();
  }

  JobDefinitionAdmin.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        managerId = json['manager_id'] as String,
        propertyId = json['property_id'] as String,
        title = json['title'] as String,
        description = json['description'] as String?,
        assignedBuildingIds = (json['assigned_building_ids'] as List<dynamic>?)
                ?.map((id) => id as String)
                .toList() ??
            [],
        dumpsterIds = (json['dumpster_ids'] as List<dynamic>?)
                ?.map((id) => id as String)
                .toList() ??
            [],
        frequency = json['frequency'] as String? ?? 'DAILY',
        weekdays = (json['weekdays'] as List<dynamic>?)
                ?.map((d) => d as int)
                .toList() ??
            [],
        intervalWeeks = json['interval_weeks'] as int?,
        startDate = DateTime.parse(json['start_date'] as String),
        endDate = json['end_date'] == null
            ? null
            : DateTime.parse(json['end_date'] as String),
        earliestStartTime = _timeFromJson(json['earliest_start_time'] as String),
        latestStartTime = _timeFromJson(json['latest_start_time'] as String),
        startTimeHint = json['start_time_hint'] == null
            ? null
            : _timeFromJson(json['start_time_hint'] as String),
        skipHolidays = json['skip_holidays'] as bool? ?? false,
        completionRules = json['completion_rules'] == null
            ? null
            : JobCompletionRulesAdmin.fromJson(
                json['completion_rules'] as Map<String, dynamic>),
        dailyPayEstimates = (json['daily_pay_estimates'] as List<dynamic>?)
                ?.map((e) => DailyPayEstimateAdmin.fromJson(
                    e as Map<String, dynamic>))
                .toList() ??
            [],
        createdAt = DateTime.parse(json['created_at'] as String),
        updatedAt = DateTime.parse(json['updated_at'] as String),
        deletedAt = json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String);

  JobDefinitionAdmin copyWith({DateTime? deletedAt}) {
    // This is a simplified copyWith for soft-delete. A full one would be much larger.
    return JobDefinitionAdmin(
      id: id,
      managerId: managerId,
      propertyId: propertyId,
      title: title,
      description: description,
      assignedBuildingIds: assignedBuildingIds,
      dumpsterIds: dumpsterIds,
      frequency: frequency,
      weekdays: weekdays,
      intervalWeeks: intervalWeeks,
      startDate: startDate,
      endDate: endDate,
      earliestStartTime: earliestStartTime,
      latestStartTime: latestStartTime,
      startTimeHint: startTimeHint,
      skipHolidays: skipHolidays,
      completionRules: completionRules,
      dailyPayEstimates: dailyPayEstimates,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'manager_id': managerId,
        'property_id': propertyId,
        'title': title,
        'description': description,
        'assigned_building_ids': assignedBuildingIds,
        'dumpster_ids': dumpsterIds,
        'frequency': frequency,
        'weekdays': weekdays,
        'interval_weeks': intervalWeeks,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'earliest_start_time': _timeToJson(earliestStartTime),
        'latest_start_time': _timeToJson(latestStartTime),
        'start_time_hint': _timeToJson(startTimeHint),
        'skip_holidays': skipHolidays,
        'completion_rules': completionRules?.toJson(),
        'daily_pay_estimates':
            dailyPayEstimates.map((e) => e.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
      };
}

class JobCompletionRulesAdmin {
  final bool proofPhotosRequired;

  JobCompletionRulesAdmin({required this.proofPhotosRequired});

  JobCompletionRulesAdmin.fromJson(Map<String, dynamic> json)
      : proofPhotosRequired =
            json['proof_photos_required'] as bool? ?? false;

  Map<String, dynamic> toJson() => {
        'proof_photos_required': proofPhotosRequired,
      };
}

class DailyPayEstimateAdmin {
  final int dayOfWeek; // 0 = Sunday, 6 = Saturday
  final double basePay;
  final int estimatedTimeMinutes;

  DailyPayEstimateAdmin({
    required this.dayOfWeek,
    required this.basePay,
    required this.estimatedTimeMinutes,
  });

  DailyPayEstimateAdmin.fromJson(Map<String, dynamic> json)
      : dayOfWeek = json['day_of_week'] as int,
        basePay = (json['base_pay'] as num).toDouble(),
        estimatedTimeMinutes = json['estimated_time_minutes'] as int;

  Map<String, dynamic> toJson() => {
        'day_of_week': dayOfWeek,
        'base_pay': basePay,
        'estimated_time_minutes': estimatedTimeMinutes,
      };
}