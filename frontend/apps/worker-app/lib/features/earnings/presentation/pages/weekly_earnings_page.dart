// worker-app/lib/features/earnings/presentation/pages/weekly_earnings_page.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

import '../../data/models/earnings_models.dart';
import 'package:poof_worker/core/theme/app_colors.dart';

// Shows the day-by-day earnings for a given WeeklyEarnings range.
class WeekEarningsDetailPage extends StatelessWidget {
  final WeeklyEarnings week;

  const WeekEarningsDetailPage({super.key, required this.week});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);

    final dailyBreakdown = week.dailyBreakdown;
    final Map<DateTime, double> dailyEarningsMap = {
      for (var earning in dailyBreakdown) earning.date: earning.totalAmount
    };

    final daysInRange = _getDaysInRange(week.weekStartDate, week.weekEndDate);
    final maxDayEarnings = dailyEarningsMap.values.fold<double>(
      0,
      (prev, el) => el > prev ? el : prev,
    );

    final startStr = DateFormat('MMM d').format(week.weekStartDate);
    final endStr = DateFormat('MMM d').format(week.weekEndDate);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              automaticallyImplyLeading: false,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              elevation: 1,
              title: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    tooltip: appLocalizations.weeklyEarningsPageBackButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '$startStr ${appLocalizations.weeklyEarningsPageTitleSuffix} $endStr',
                      style: const TextStyle(
                        fontSize: 22, // Slightly smaller for app bar
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      '${appLocalizations.weeklyEarningsPageTotalLabel}${week.weeklyTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (daysInRange.isEmpty || maxDayEarnings == 0)
                      Text(appLocalizations.weeklyEarningsPageNoEarnings)
                    else
                      _buildFlChartBarChart(
                        daysInRange,
                        dailyEarningsMap,
                        maxDayEarnings,
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            // Build the list of jobs grouped by date
            ..._buildJobHistoryList(context, dailyBreakdown),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildJobHistoryList(
      BuildContext context, List<DailyEarning> breakdown) {
    if (breakdown.isEmpty) return [const SliverToBoxAdapter(child: SizedBox())];

    final widgets = <Widget>[];
    for (final daily in breakdown) {
      // Add a date header for each day
      widgets.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            DateFormat.yMMMMEEEEd().format(daily.date),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ));

      // Add a list of job cards for that day
      widgets.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final job = daily.jobs[index];
            return _CompletedJobCard(job: job);
          },
          childCount: daily.jobs.length,
        ),
      ));
    }
    return widgets;
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

  Widget _buildFlChartBarChart(
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

    final roundUp = ((maxDayEarnings / 10).ceil() * 10).toDouble() + 10;

    return SizedBox(
      height: 250, // Reduced height for the chart
      child: BarChart(
        BarChartData(
          maxY: roundUp,
          minY: 0,
          groupsSpace: 12,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipPadding: const EdgeInsets.all(8),
              getTooltipItem: (group, _, rod, _) {
                final day = days[group.x];
                final dayStr = DateFormat('MMM d').format(day);
                return BarTooltipItem(
                  '$dayStr\n\$${rod.toY.toStringAsFixed(2)}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: roundUp > 50 ? 20 : 10,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value <= 0 || value > roundUp) return const SizedBox();
                  return Text(
                    '\$${value.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= days.length) return const SizedBox();
                  final dayStr = DateFormat('E\nd').format(days[idx]);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      dayStr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: roundUp > 50 ? 20 : 10,
            getDrawingHorizontalLine: (val) => FlLine(
              color: Colors.grey[300]!,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: barGroups,
        ),
      ),
    );
  }
}

class _CompletedJobCard extends StatelessWidget {
  final CompletedJob job;
  const _CompletedJobCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final completedTime = job.completedAt != null
        ? DateFormat.jm().format(job.completedAt!.toLocal())
        : 'N/A';
    final duration = job.durationMinutes != null
        ? '${job.durationMinutes} ${appLocalizations.timeUnitMinutes.toLowerCase()}'
        : 'N/A';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    job.propertyName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '+\$${job.pay.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
              Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _InfoPill(
                  icon: Icons.check_circle_outline,
                  text: appLocalizations
                      .completedJobBottomSheetCompletedLabel(completedTime),
                  foregroundColor: Colors.grey.shade800,
                  backgroundColor: Colors.grey.shade100,
                ),
                _InfoPill(
                  icon: Icons.timer_outlined,
                  text: appLocalizations
                      .completedJobBottomSheetTimeToCompleteLabel(duration),
                  foregroundColor: Colors.grey.shade800,
                  backgroundColor: Colors.grey.shade100,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? foregroundColor;
  final Color? backgroundColor;

  const _InfoPill({
    required this.icon,
    required this.text,
    this.foregroundColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = foregroundColor ?? Colors.grey.shade800;
    final Color bg = backgroundColor ?? Colors.grey.shade100;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 14, color: fg),
          ),
        ],
      ),
    );
  }
}
