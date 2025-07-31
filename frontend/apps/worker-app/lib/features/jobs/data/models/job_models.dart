// worker-app/lib/features/jobs/data/models/job_models.dart

import 'package:poof_flutter_auth/poof_flutter_auth.dart' show JsonSerializable;

enum TransportMode {
  car,
  walk,
}

enum JobInstanceStatus {
  open,
  assigned,
  inProgress,
  completed,
  retired,
  canceled,
}

enum UnitVerificationStatus { pending, verified, dumped, failed }

UnitVerificationStatus unitVerificationStatusFromString(String raw) {
  switch (raw.toUpperCase()) {
    case 'PENDING':
      return UnitVerificationStatus.pending;
    case 'VERIFIED':
      return UnitVerificationStatus.verified;
    case 'DUMPED':
      return UnitVerificationStatus.dumped;
    case 'FAILED':
      return UnitVerificationStatus.failed;
    default:
      throw ArgumentError('Invalid UnitVerificationStatus: $raw');
  }
}

String unitVerificationStatusToString(UnitVerificationStatus status) {
  switch (status) {
    case UnitVerificationStatus.pending:
      return 'PENDING';
    case UnitVerificationStatus.verified:
      return 'VERIFIED';
    case UnitVerificationStatus.dumped:
      return 'DUMPED';
    case UnitVerificationStatus.failed:
      return 'FAILED';
  }
}

class UnitVerification {
  final String unitId;
  final String buildingId;
  final String unitNumber;
  final UnitVerificationStatus status;

  const UnitVerification({
    required this.unitId,
    required this.buildingId,
    required this.unitNumber,
    required this.status,
  });

  factory UnitVerification.fromJson(Map<String, dynamic> json) {
    return UnitVerification(
      unitId: json['unit_id'] as String,
      buildingId: json['building_id'] as String,
      unitNumber: json['unit_number'] as String,
      status: unitVerificationStatusFromString(json['status'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'unit_id': unitId,
        'building_id': buildingId,
        'unit_number': unitNumber,
        'status': unitVerificationStatusToString(status),
      };
}

JobInstanceStatus jobInstanceStatusFromString(String raw) {
  switch (raw.toUpperCase()) {
    case 'OPEN':
      return JobInstanceStatus.open;
    case 'ASSIGNED':
      return JobInstanceStatus.assigned;
    case 'IN_PROGRESS':
      return JobInstanceStatus.inProgress;
    case 'COMPLETED':
      return JobInstanceStatus.completed;
    case 'RETIRED':
      return JobInstanceStatus.retired;
    case 'CANCELED':
      return JobInstanceStatus.canceled;
    default:
      throw ArgumentError('Invalid JobInstanceStatus: $raw');
  }
}

/// For multi-building properties
class Building {
  final String buildingId;
  final String name;
  final double latitude;
  final double longitude;
  final List<UnitVerification> units;

  const Building({
    required this.buildingId,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.units = const [],
  });

  factory Building.fromJson(Map<String, dynamic> json) {
    final unitsList = <UnitVerification>[];
    if (json['units'] is List) {
      for (final u in (json['units'] as List)) {
        unitsList.add(UnitVerification.fromJson(u as Map<String, dynamic>));
      }
    }
    return Building(
      buildingId: json['building_id'] as String,
      name: json['building_name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      units: unitsList,
    );
  }
}

class Dumpster {
  final String dumpsterId;
  final String number;
  final double latitude;
  final double longitude;

  const Dumpster({
    required this.dumpsterId,
    required this.number,
    required this.latitude,
    required this.longitude,
  });

  factory Dumpster.fromJson(Map<String, dynamic> json) {
    return Dumpster(
      dumpsterId: json['dumpster_id'] as String,
      number: json['dumpster_number'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

class Property {
  final String propertyId;
  final String propertyName;
  final String address;
  final String city;
  final String state;
  final String zipCode;
  final double latitude;
  final double longitude;

  const Property({
    required this.propertyId,
    required this.propertyName,
    required this.address,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.latitude,
    required this.longitude,
  });

  factory Property.fromJson(Map<String, dynamic> json) {
    return Property(
      propertyId: json['property_id'] as String,
      propertyName: json['property_name'] as String,
      address: json['address'] as String,
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      zipCode: json['zip_code'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

/// A "Job Instance" from the server (or from dummy data).
class JobInstance {
  final String instanceId;
  final String definitionId;
  final String propertyId;
  final String serviceDate; // "YYYY-MM-DD"
  final JobInstanceStatus status;
  final double pay;

  final Property property;
  final int numberOfBuildings;
  final List<Building> buildings;
  final int numberOfDumpsters;
  final List<Dumpster> dumpsters;

  final String startTimeHint;
  final String workerStartTimeHint;

  final String propertyServiceWindowStart;
  final String workerServiceWindowStart;
  final String propertyServiceWindowEnd;
  final String workerServiceWindowEnd;

  final double distanceMiles;
  final int? travelMinutes;

  final int estimatedTimeMinutes;
  final TransportMode transportMode;
  final DateTime? checkInAt; // NEW

  const JobInstance({
    required this.instanceId,
    required this.definitionId,
    required this.propertyId,
    required this.serviceDate,
    required this.status,
    required this.pay,
    required this.property,
    required this.numberOfBuildings,
    required this.buildings,
    required this.numberOfDumpsters,
    required this.dumpsters,
    required this.startTimeHint,
    required this.workerStartTimeHint,
    required this.propertyServiceWindowStart,
    required this.workerServiceWindowStart,
    required this.propertyServiceWindowEnd,
    required this.workerServiceWindowEnd,
    required this.distanceMiles,
    required this.travelMinutes,
    required this.estimatedTimeMinutes,
    required this.transportMode,
    this.checkInAt, // NEW
  });

  factory JobInstance.fromJson(Map<String, dynamic> json) {
    final bList = <Building>[];
    if (json['buildings'] is List) {
      for (final b in (json['buildings'] as List)) {
        bList.add(Building.fromJson(b as Map<String, dynamic>));
      }
    }

    final dList = <Dumpster>[];
    if (json['dumpsters'] is List) {
      for (final d in (json['dumpsters'] as List)) {
        dList.add(Dumpster.fromJson(d as Map<String, dynamic>));
      }
    }

    final checkInAtRaw = json['check_in_at'] as String?;

    return JobInstance(
      instanceId: json['instance_id'] as String,
      definitionId: json['definition_id'] as String,
      propertyId: json['property_id'] as String,
      serviceDate: json['service_date'] as String,
      status: jobInstanceStatusFromString(json['status'] as String),
      pay: (json['pay'] as num).toDouble(),
      property: Property.fromJson(json['property'] as Map<String, dynamic>),
      numberOfBuildings: json['number_of_buildings'] as int,
      buildings: bList,
      numberOfDumpsters: json['number_of_dumpsters'] as int,
      dumpsters: dList,
      startTimeHint: (json['start_time_hint'] as String?) ?? '',
      workerStartTimeHint: (json['worker_start_time_hint'] as String?) ?? '',
      propertyServiceWindowStart: (json['property_service_window_start'] as String?) ?? '',
      workerServiceWindowStart: (json['worker_service_window_start'] as String?) ?? '',
      propertyServiceWindowEnd: (json['property_service_window_end'] as String?) ?? '',
      workerServiceWindowEnd: (json['worker_service_window_end'] as String?) ?? '',
      distanceMiles: (json['distance_miles'] as num?)?.toDouble() ?? 0.0,
      travelMinutes: json['travel_minutes'] as int?,
      estimatedTimeMinutes: (json['estimated_time_minutes'] as int?) ?? 60,
      transportMode: TransportMode.car,
      checkInAt: checkInAtRaw != null ? DateTime.parse(checkInAtRaw) : null, // NEW
    );
  }

  String get distanceLabel {
    if (distanceMiles <= 0.0) {
      return 'N/A';
    }
    return '${distanceMiles.toStringAsFixed(1)} miles';
  }

  /// MODIFIED: Formats time into "1 hr 30 min" instead of "1.5 hrs".
  String get displayTime {
    if (estimatedTimeMinutes <= 0) return 'N/A';
    if (estimatedTimeMinutes < 60) return '$estimatedTimeMinutes min';

    final hours = estimatedTimeMinutes ~/ 60;
    final minutes = estimatedTimeMinutes % 60;

    if (minutes == 0) {
      return '$hours hr${hours == 1 ? '' : 's'}';
    }

    return '$hours hr $minutes min';
  }

  String get displayTravelTime {
    if (travelMinutes == null || travelMinutes! <= 0) return 'N/A';
    return '$travelMinutes min';
  }

  /// NEW: Generates a subtitle string for building information.
  String get buildingSubtitle {
    if (buildings.isEmpty) {
      return '';
    }
    final firstBuildingName = buildings.first.name;
    if (numberOfBuildings == 1) {
      return firstBuildingName;
    }
    final others = numberOfBuildings - 1;
    // e.g., "Building A & 2 more"
    return '$firstBuildingName & $others more';
  }
}

class JobLocationActionRequest implements JsonSerializable {
  final String instanceId;
  final double lat;
  final double lng;
  final double accuracy;
  final int timestamp;
  final bool isMock;

  JobLocationActionRequest({
    required this.instanceId,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.timestamp,
    required this.isMock,
  });

  @override
  Map<String, dynamic> toJson() => {
        'instance_id': instanceId,
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'timestamp': timestamp,
        'is_mock': isMock,
      };

  Map<String, String> toFormFields() => {
        'instance_id': instanceId,
        'lat': lat.toString(),
        'lng': lng.toString(),
        'accuracy': accuracy.toString(),
        'timestamp': timestamp.toString(),
        'is_mock': isMock.toString(),
      };
}

class JobActionRequest implements JsonSerializable {
  final String instanceId;
  JobActionRequest(this.instanceId);

  @override
  Map<String, dynamic> toJson() => {
        'instance_id': instanceId,
      };
}

class ListJobsResponse {
  final List<JobInstance> results;
  final int page;
  final int size;
  final int total;

  const ListJobsResponse({
    required this.results,
    required this.page,
    required this.size,
    required this.total,
  });

  factory ListJobsResponse.fromJson(Map<String, dynamic> json) {
    final list = <JobInstance>[];
    if (json['results'] is List) {
      for (final item in (json['results'] as List)) {
        list.add(JobInstance.fromJson(item as Map<String, dynamic>));
      }
    }
    return ListJobsResponse(
      results: list,
      page: json['page'] as int,
      size: json['size'] as int,
      total: json['total'] as int,
    );
  }
}

class JobInstanceActionResponse {
  final JobInstance updated;
  const JobInstanceActionResponse({required this.updated});

  factory JobInstanceActionResponse.fromJson(Map<String, dynamic> json) {
    return JobInstanceActionResponse(
      updated: JobInstance.fromJson(json['updated'] as Map<String, dynamic>),
    );
  }
}

extension JobInstanceCopyWith on JobInstance {
  JobInstance copyWith({
    JobInstanceStatus? status,
    double? pay,
    Property? property,
    List<Building>? buildings,
    String? propertyServiceWindowStart,
    String? workerServiceWindowStart,
    String? propertyServiceWindowEnd,
    String? workerServiceWindowEnd,
    double? distanceMiles,
    int? travelMinutes,
    int? estimatedTimeMinutes,
    TransportMode? transportMode,
    DateTime? checkInAt, // NEW
  }) {
    return JobInstance(
      instanceId: instanceId,
      definitionId: definitionId,
      propertyId: propertyId,
      serviceDate: serviceDate,
      status: status ?? this.status,
      pay: pay ?? this.pay,
      property: property ?? this.property,
      numberOfBuildings: numberOfBuildings,
      buildings: buildings ?? this.buildings,
      numberOfDumpsters: numberOfDumpsters,
      dumpsters: dumpsters,
      startTimeHint: startTimeHint,
      workerStartTimeHint: workerStartTimeHint,
      propertyServiceWindowStart: propertyServiceWindowStart ?? this.propertyServiceWindowStart,
      workerServiceWindowStart: workerServiceWindowStart ?? this.workerServiceWindowStart,
      propertyServiceWindowEnd: propertyServiceWindowEnd ?? this.propertyServiceWindowEnd,
      workerServiceWindowEnd: workerServiceWindowEnd ?? this.workerServiceWindowEnd,
      distanceMiles: distanceMiles ?? this.distanceMiles,
      travelMinutes: travelMinutes ?? this.travelMinutes,
      estimatedTimeMinutes: estimatedTimeMinutes ?? this.estimatedTimeMinutes,
      transportMode: transportMode ?? this.transportMode,
      checkInAt: checkInAt ?? this.checkInAt, // NEW
    );
  }
}

class DefinitionGroup {
  final String definitionId;
  final String propertyName;
  final String propertyAddress;
  final double distanceMiles;
  final double pay; // average pay
  final TransportMode transportMode;
  final List<JobInstance> instances;

  const DefinitionGroup({
    required this.definitionId,
    required this.propertyName,
    required this.propertyAddress,
    required this.distanceMiles,
    required this.pay,
    required this.transportMode,
    required this.instances,
  });

  double get avgEstimatedTimeMinutes {
    if (instances.isEmpty) return 0.0;
    final totalMinutes = instances.fold<double>(
        0, (sum, i) => sum + i.estimatedTimeMinutes);
    return totalMinutes / instances.length;
  }

  int? get avgTravelMinutes {
    if (instances.isEmpty) return null;
    final travelTimes =
        instances.map((i) => i.travelMinutes).whereType<int>().toList();
    if (travelTimes.isEmpty) return null;
    return (travelTimes.fold<int>(0, (sum, t) => sum + t) /
            travelTimes.length)
        .round();
  }

  /// MODIFIED: Formats time into "1 hr 30 min" instead of "1.5 hrs".
  String get displayAvgTime {
    final avgMins = avgEstimatedTimeMinutes;
    if (avgMins <= 0) return 'N/A';

    final totalMinutesInt = avgMins.round();
    if (totalMinutesInt < 60) return '$totalMinutesInt min';
    
    final hours = totalMinutesInt ~/ 60;
    final minutes = totalMinutesInt % 60;

    if (minutes == 0) {
      return '$hours hr${hours == 1 ? '' : 's'}';
    }

    return '$hours hr $minutes min';
  }

   String get displayAvgTravelTime {
    final avgMins = avgTravelMinutes;
    if (avgMins == null || avgMins <= 0) return 'N/A';
    return '$avgMins min';
  }

  /// NEW: Gets the building subtitle from the first instance in the group.
  String get buildingSubtitle {
    if (instances.isEmpty) return '';
    // Assuming all instances in a group have the same buildings,
    // we can just use the first one's subtitle logic.
    return instances.first.buildingSubtitle;
  }
}

List<DefinitionGroup> groupOpenJobs(List<JobInstance> jobs) {
  final map = <String, List<JobInstance>>{};
  for (final j in jobs) {
    map.putIfAbsent(j.definitionId, () => []).add(j);
  }

  final result = <DefinitionGroup>[];

  map.forEach((defId, instList) {
    if (instList.isEmpty) return;
    final first = instList.first;
    final avgPay = instList.fold<double>(0, (sum, i) => sum + i.pay) / instList.length;

    result.add(
      DefinitionGroup(
        definitionId: defId,
        propertyName: first.property.propertyName,
        propertyAddress: first.property.address,
        distanceMiles: first.distanceMiles,
        pay: avgPay,
        transportMode: first.transportMode,
        instances: instList,
      ),
    );
  });

  return result;
}
