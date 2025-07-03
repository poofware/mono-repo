// lib/features/earnings/data/models/earnings_models.dart

enum PayoutStatus {
  pending,
  processing,
  paid,
  failed,
  current, // For the ongoing, not-yet-payout-eligible week
  unknown,
}

PayoutStatus _payoutStatusFromString(String raw) {
  switch (raw.toUpperCase()) {
    case 'PENDING':
      return PayoutStatus.pending;
    case 'PROCESSING':
      return PayoutStatus.processing;
    case 'PAID':
      return PayoutStatus.paid;
    case 'FAILED':
      return PayoutStatus.failed;
    case 'CURRENT':
      return PayoutStatus.current;
    default:
      return PayoutStatus.unknown;
  }
}

class CompletedJob {
  final String instanceId;
  final String propertyName;
  final double pay;
  final DateTime? completedAt;
  final int? durationMinutes;

  const CompletedJob({
    required this.instanceId,
    required this.propertyName,
    required this.pay,
    this.completedAt,
    this.durationMinutes,
  });

  factory CompletedJob.fromJson(Map<String, dynamic> json) {
    return CompletedJob(
      instanceId: json['instance_id'] as String,
      propertyName: json['property_name'] as String? ?? 'Unknown Property',
      pay: (json['pay'] as num).toDouble(),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      durationMinutes: json['duration_minutes'] as int?,
    );
  }
}

class DailyEarning {
  final DateTime date;
  final double totalAmount;
  final int jobCount;
  final List<CompletedJob> jobs;

  const DailyEarning({
    required this.date,
    required this.totalAmount,
    required this.jobCount,
    required this.jobs,
  });

  factory DailyEarning.fromJson(Map<String, dynamic> json) {
    var jobList = <CompletedJob>[];
    if (json['jobs'] is List) {
      jobList = (json['jobs'] as List)
          .map((item) => CompletedJob.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return DailyEarning(
      date: DateTime.parse(json['date'] as String),
      totalAmount: (json['total_amount'] as num).toDouble(),
      jobCount: json['job_count'] as int,
      jobs: jobList,
    );
  }
}

class WeeklyEarnings {
  final DateTime weekStartDate;
  final DateTime weekEndDate;
  final double weeklyTotal;
  final int jobCount;
  final PayoutStatus payoutStatus;
  final List<DailyEarning> dailyBreakdown;
  final String? failureReason;
  final bool requiresUserAction;

  const WeeklyEarnings({
    required this.weekStartDate,
    required this.weekEndDate,
    required this.weeklyTotal,
    required this.jobCount,
    required this.payoutStatus,
    required this.dailyBreakdown,
    this.failureReason,
    this.requiresUserAction = false,
  });

  factory WeeklyEarnings.fromJson(Map<String, dynamic> json) {
    var dailyList = <DailyEarning>[];
    if (json['daily_breakdown'] is List) {
      dailyList = (json['daily_breakdown'] as List)
          .map((item) => DailyEarning.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return WeeklyEarnings(
      weekStartDate: DateTime.parse(json['week_start_date'] as String),
      weekEndDate: DateTime.parse(json['week_end_date'] as String),
      weeklyTotal: (json['weekly_total'] as num).toDouble(),
      jobCount: json['job_count'] as int,
      payoutStatus: _payoutStatusFromString(json['payout_status'] as String),
      dailyBreakdown: dailyList,
      failureReason: json['failure_reason'] as String?,
      requiresUserAction: json['requires_user_action'] as bool? ?? false,
    );
  }
}

class EarningsSummary {
  final double twoMonthTotal;
  final WeeklyEarnings? currentWeek;
  final List<WeeklyEarnings> pastWeeks;
  final DateTime nextPayoutDate;

  const EarningsSummary({
    required this.twoMonthTotal,
    this.currentWeek,
    required this.pastWeeks,
    required this.nextPayoutDate,
  });

  factory EarningsSummary.fromJson(Map<String, dynamic> json) {
    var pastList = <WeeklyEarnings>[];
    if (json['past_weeks'] is List) {
      pastList = (json['past_weeks'] as List)
          .map((item) => WeeklyEarnings.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return EarningsSummary(
      twoMonthTotal: (json['two_month_total'] as num).toDouble(),
      currentWeek: json['current_week'] == null
          ? null
          : WeeklyEarnings.fromJson(
              json['current_week'] as Map<String, dynamic>),
      pastWeeks: pastList,
      nextPayoutDate: DateTime.parse(json['next_payout_date'] as String),
    );
  }
}
