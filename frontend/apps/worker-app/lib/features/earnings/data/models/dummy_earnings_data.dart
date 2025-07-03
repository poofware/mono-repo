// lib/features/earnings/data/models/dummy_earnings_data.dart

import 'earnings_models.dart';

/// Helper to strip the time component from a DateTime, making it a pure date.
DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

class DummyEarningsData {
  static final EarningsSummary summary = EarningsSummary(
    twoMonthTotal: 1234.56,
    nextPayoutDate: _dateOnly(DateTime.now().add(const Duration(days: 4))),
    currentWeek: WeeklyEarnings(
      weekStartDate: _dateOnly(DateTime.now().subtract(const Duration(days: 3))),
      weekEndDate: _dateOnly(DateTime.now().add(const Duration(days: 3))),
      weeklyTotal: 150.75,
      jobCount: 5,
      payoutStatus: PayoutStatus.current,
      dailyBreakdown: [
        DailyEarning(
          date: _dateOnly(DateTime.now().subtract(const Duration(days: 2))),
          totalAmount: 50.25,
          jobCount: 2,
          jobs: [
            CompletedJob(instanceId: 'job1', propertyName: 'Current Week Apartments', pay: 25.00, completedAt: DateTime.now().subtract(const Duration(days: 2, hours: 5)), durationMinutes: 45),
            CompletedJob(instanceId: 'job2', propertyName: 'Downtown Lofts', pay: 25.25, completedAt: DateTime.now().subtract(const Duration(days: 2, hours: 4)), durationMinutes: 50),
          ],
        ),
        DailyEarning(
          date: _dateOnly(DateTime.now().subtract(const Duration(days: 1))),
          totalAmount: 75.50,
          jobCount: 2,
          jobs: [
            CompletedJob(instanceId: 'job3', propertyName: 'The Grand Residences', pay: 40.00, completedAt: DateTime.now().subtract(const Duration(days: 1, hours: 6)), durationMinutes: 65),
            CompletedJob(instanceId: 'job4', propertyName: 'Riverbend Commons', pay: 35.50, completedAt: DateTime.now().subtract(const Duration(days: 1, hours: 3)), durationMinutes: 55),
          ],
        ),
        DailyEarning(
          date: _dateOnly(DateTime.now()),
          totalAmount: 25.00,
          jobCount: 1,
          jobs: [
             CompletedJob(instanceId: 'job5', propertyName: 'Historic Main Street', pay: 25.00, completedAt: DateTime.now().subtract(const Duration(hours: 2)), durationMinutes: 40),
          ],
        ),
      ],
    ),
    pastWeeks: [
      WeeklyEarnings(
        weekStartDate: _dateOnly(DateTime.now().subtract(const Duration(days: 10))),
        weekEndDate: _dateOnly(DateTime.now().subtract(const Duration(days: 4))),
        weeklyTotal: 320.50,
        jobCount: 10,
        payoutStatus: PayoutStatus.failed,
        dailyBreakdown: [
          DailyEarning(date: _dateOnly(DateTime.now().subtract(const Duration(days: 10))), totalAmount: 50.00, jobCount: 2, jobs: [
            CompletedJob(instanceId: 'job6', propertyName: 'Willow Creek Flats', pay: 25.00, completedAt: DateTime.now().subtract(const Duration(days: 10, hours: 5)), durationMinutes: 50),
            CompletedJob(instanceId: 'job7', propertyName: 'Oak Ridge Lofts', pay: 25.00, completedAt: DateTime.now().subtract(const Duration(days: 10, hours: 3)), durationMinutes: 48),
          ]),
          DailyEarning(date: _dateOnly(DateTime.now().subtract(const Duration(days: 9))), totalAmount: 45.50, jobCount: 2, jobs: [
            CompletedJob(instanceId: 'job8', propertyName: 'Willow Creek Flats', pay: 20.00, completedAt: DateTime.now().subtract(const Duration(days: 9, hours: 6)), durationMinutes: 42),
            CompletedJob(instanceId: 'job9', propertyName: 'Oak Ridge Lofts', pay: 25.50, completedAt: DateTime.now().subtract(const Duration(days: 9, hours: 4)), durationMinutes: 51),
          ]),
          DailyEarning(date: _dateOnly(DateTime.now().subtract(const Duration(days: 8))), totalAmount: 60.00, jobCount: 2, jobs: [
            CompletedJob(instanceId: 'job10', propertyName: 'Magnolia Park', pay: 30.00, completedAt: DateTime.now().subtract(const Duration(days: 8, hours: 7)), durationMinutes: 55),
            CompletedJob(instanceId: 'job11', propertyName: 'Magnolia Park', pay: 30.00, completedAt: DateTime.now().subtract(const Duration(days: 8, hours: 2)), durationMinutes: 58),
          ]),
          DailyEarning(date: _dateOnly(DateTime.now().subtract(const Duration(days: 7))), totalAmount: 75.00, jobCount: 2, jobs: [
            CompletedJob(instanceId: 'job12', propertyName: 'Willow Creek Flats', pay: 35.00, completedAt: DateTime.now().subtract(const Duration(days: 7, hours: 5)), durationMinutes: 60),
            CompletedJob(instanceId: 'job13', propertyName: 'Oak Ridge Lofts', pay: 40.00, completedAt: DateTime.now().subtract(const Duration(days: 7, hours: 3)), durationMinutes: 68),
          ]),
          DailyEarning(date: _dateOnly(DateTime.now().subtract(const Duration(days: 5))), totalAmount: 90.00, jobCount: 2, jobs: [
            CompletedJob(instanceId: 'job14', propertyName: 'The Grand Residences', pay: 45.00, completedAt: DateTime.now().subtract(const Duration(days: 5, hours: 8)), durationMinutes: 70),
            CompletedJob(instanceId: 'job15', propertyName: 'Riverbend Commons', pay: 45.00, completedAt: DateTime.now().subtract(const Duration(days: 5, hours: 6)), durationMinutes: 72),
          ]),
        ],
        failureReason: 'account_closed',
        requiresUserAction: true,
      ),
      WeeklyEarnings(
        weekStartDate: _dateOnly(DateTime.now().subtract(const Duration(days: 17))),
        weekEndDate: _dateOnly(DateTime.now().subtract(const Duration(days: 11))),
        weeklyTotal: 280.00,
        jobCount: 8,
        payoutStatus: PayoutStatus.paid,
        dailyBreakdown: [
          DailyEarning(date: _dateOnly(DateTime.now().subtract(const Duration(days: 17))), totalAmount: 40.00, jobCount: 1, jobs: [
             CompletedJob(instanceId: 'job16', propertyName: 'Willow Creek Flats', pay: 40.00, completedAt: DateTime.now().subtract(const Duration(days: 17, hours: 5)), durationMinutes: 60),
          ]),
          DailyEarning(date: _dateOnly(DateTime.now().subtract(const Duration(days: 16))), totalAmount: 35.00, jobCount: 1, jobs: [
             CompletedJob(instanceId: 'job17', propertyName: 'Oak Ridge Lofts', pay: 35.00, completedAt: DateTime.now().subtract(const Duration(days: 16, hours: 4)), durationMinutes: 55),
          ]),
          DailyEarning(date: _dateOnly(DateTime.now().subtract(const Duration(days: 15))), totalAmount: 50.00, jobCount: 2, jobs: [
            CompletedJob(instanceId: 'job18', propertyName: 'Magnolia Park', pay: 25.00, completedAt: DateTime.now().subtract(const Duration(days: 15, hours: 6)), durationMinutes: 45),
            CompletedJob(instanceId: 'job19', propertyName: 'The Grand Residences', pay: 25.00, completedAt: DateTime.now().subtract(const Duration(days: 15, hours: 3)), durationMinutes: 47),
          ]),
          DailyEarning(date: _dateOnly(DateTime.now().subtract(const Duration(days: 14))), totalAmount: 65.00, jobCount: 2, jobs: [
            CompletedJob(instanceId: 'job20', propertyName: 'Riverbend Commons', pay: 30.00, completedAt: DateTime.now().subtract(const Duration(days: 14, hours: 5)), durationMinutes: 52),
            CompletedJob(instanceId: 'job21', propertyName: 'Historic Main Street', pay: 35.00, completedAt: DateTime.now().subtract(const Duration(days: 14, hours: 2)), durationMinutes: 58),
          ]),
          DailyEarning(date: _dateOnly(DateTime.now().subtract(const Duration(days: 12))), totalAmount: 90.00, jobCount: 2, jobs: [
            CompletedJob(instanceId: 'job22', propertyName: 'Willow Creek Flats', pay: 45.00, completedAt: DateTime.now().subtract(const Duration(days: 12, hours: 7)), durationMinutes: 70),
            CompletedJob(instanceId: 'job23', propertyName: 'Oak Ridge Lofts', pay: 45.00, completedAt: DateTime.now().subtract(const Duration(days: 12, hours: 5)), durationMinutes: 71),
          ]),
        ],
      ),
    ],
  );
}
