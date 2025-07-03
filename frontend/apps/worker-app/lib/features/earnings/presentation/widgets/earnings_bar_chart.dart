// worker-app/lib/features/earnings/presentation/widgets/earnings_bar_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/features/earnings/data/models/earnings_models.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

class EarningsBarChart extends StatelessWidget {
  final WeeklyEarnings? week;
  final String title;

  const EarningsBarChart({
    super.key,
    this.week,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final weeklyTotal = week?.weeklyTotal ?? 0.0;
    final dailyEarningsMap = week != null
        ? {
            for (var earning in week!.dailyBreakdown)
              earning.date: earning.totalAmount
          }
        : <DateTime, double>{};

    final daysInRange = week != null
        ? _getDaysInRange(week!.weekStartDate, week!.weekEndDate)
        : <DateTime>[]; // FIX: Explicitly type the empty list.
    final maxDayEarnings = dailyEarningsMap.values.fold<double>(
      0,
      (prev, el) => el > prev ? el : prev,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '\$${weeklyTotal.toStringAsFixed(2)}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (week == null || daysInRange.isEmpty || maxDayEarnings == 0)
            SizedBox(
              height: 200,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(AppLocalizations.of(context)
                      .weeklyEarningsPageNoEarnings),
                ),
              ),
            )
          else
            _buildChart(daysInRange, dailyEarningsMap, maxDayEarnings),
        ],
      ),
    );
  }

  List<DateTime> _getDaysInRange(DateTime start, DateTime end) {
    final List<DateTime> days = [];
    DateTime current = start;
    while (!current.isAfter(end)) {
      days.add(current);
      current = current.add(const Duration(days: 1));
    }
    return days;
  }

  Widget _buildChart(
    List<DateTime> days,
    Map<DateTime, double> dailyEarningsMap,
    double maxDayEarnings,
  ) {
    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < days.length; i++) {
      final day = days[i];
      final earnings = dailyEarningsMap[day] ?? 0;
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: earnings,
              color: AppColors.poofColor,
              borderRadius: BorderRadius.circular(4),
              width: 18,
            ),
          ],
        ),
      );
    }

    final roundUp = (maxDayEarnings / 10).ceil() * 10.0;
    final interval = (roundUp > 50) ? 20.0 : 10.0;

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: roundUp + interval,
          minY: 0,
          groupsSpace: 12,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, _, rod, __) {
                final day = days[group.x];
                final dayStr = DateFormat('MMM d').format(day);
                return BarTooltipItem(
                  '$dayStr\n\$${rod.toY.toStringAsFixed(2)}',
                  const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= days.length) return const SizedBox();
                  final dayStr = DateFormat('E').format(days[idx]);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      dayStr.substring(0, 1), // Single letter for day
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }
}
