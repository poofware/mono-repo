// lib/features/jobs/presentation/widgets/job_history_stats_card.dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:poof_pm/features/jobs/data/models/job_instance_pm.dart';
import 'package:poof_pm/features/jobs/data/models/job_status.dart';
import 'package:poof_pm/features/jobs/state/job_history_state.dart';

class JobHistoryStatsCard extends StatelessWidget {
  final List<JobInstancePm> entries;
  final JobHistoryFilters filters;

  const JobHistoryStatsCard({
    super.key,
    required this.entries,
    required this.filters,
  });

  /// Generates the card title dynamically based on the active date filter.
  String _generateTitle(JobHistoryFilters filters) {
    final now = DateTime.now();
    final currentYear = now.year;
    final displayFormat = DateFormat('MMM d, yyyy');

    switch (filters.dateRangePreset) {
      case DateRangePreset.last7days:
        return 'Last 7 Days';
      case DateRangePreset.last30days:
        return 'Last 30 Days';
      case DateRangePreset.last90days:
        return 'Last 90 Days';
      case DateRangePreset.thisYear:
        return 'This Year ($currentYear)';
      case DateRangePreset.lastYear:
        return 'Last Year (${currentYear - 1})';
      case DateRangePreset.custom:
        final start = filters.customStartDate;
        final end = filters.customEndDate;
        if (start != null && end != null) {
          // If start and end are the same day, just show one date.
          if (start.year == end.year && start.month == end.month && start.day == end.day) {
            return displayFormat.format(start);
          }
          return '${displayFormat.format(start)} - ${displayFormat.format(end)}';
        } else if (start != null) {
          return 'From ${displayFormat.format(start)}';
        } else if (end != null) {
          return 'Until ${displayFormat.format(end)}';
        }
        return 'Custom Range';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.shade200, width: 1),
            borderRadius: const BorderRadius.all(Radius.circular(12))),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No data for this period.'),
          ),
        ),
      );
    }

    // --- Aggregate basic stats ---
    final completed = entries.where((e) => jobStatusFromString(e.status) == JobStatus.completed).length;
    final upcoming = entries.where((e) => jobStatusFromString(e.status) == JobStatus.upcoming).length;
    final missed = entries.where((e) => jobStatusFromString(e.status) == JobStatus.missed).length;
    final partial = entries.where((e) => jobStatusFromString(e.status) == JobStatus.partiallyCompleted).length;

    // MODIFICATION: Denominator now only includes "scorable" jobs.
    final totalScorableJobs = completed + missed + partial;

    // Handle division by zero.
    final completedPct = totalScorableJobs > 0 ? completed / totalScorableJobs : 0.0;

    final upcomingUI = StatusUI.from(JobStatus.upcoming);
    final missedUI = StatusUI.from(JobStatus.missed);
    final partialUI = StatusUI.from(JobStatus.partiallyCompleted);
    final completedUI = StatusUI.from(JobStatus.completed);

    Widget _metric(String label, int value, {Color? color}) => Row(
          children: [
            Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(color: color ?? Colors.grey, shape: BoxShape.circle)),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            Text('$value', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
        );

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade200, width: 1),
        borderRadius: const BorderRadius.all(Radius.circular(12))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // MODIFICATION: Title is now dynamic.
            Text(_generateTitle(filters),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 16),
            Center(
              child: _CompletionRing(
                completedPercent: completedPct,
                missedPercent: 0,
                partialPercent: 0,
                completedColor: Colors.green,
                missedColor: missedUI.bg,
                partialColor: partialUI.bg,
              ),
            ),
            const SizedBox(height: 16),
            _metric('Completed', completed, color: completedUI.bg),
            const SizedBox(height: 8),
            _metric('Upcoming', upcoming, color: upcomingUI.bg),
            const SizedBox(height: 8),
            _metric('Missed', missed, color: missedUI.bg),
            const SizedBox(height: 8),
            _metric('Partial', partial, color: partialUI.bg),
          ],
        ),
      ),
    );
  }
}

// Custom widget to display the segmented progress ring
class _CompletionRing extends StatelessWidget {
  final double completedPercent;
  final double missedPercent;
  final double partialPercent;
  final Color completedColor;
  final Color missedColor;
  final Color partialColor;

  const _CompletionRing({
    required this.completedPercent,
    required this.missedPercent,
    required this.partialPercent,
    required this.completedColor,
    required this.missedColor,
    required this.partialColor,
  });

  @override
  Widget build(BuildContext context) {
    final int percentage = (completedPercent * 100).round();
    return SizedBox(
      width: 240, // Increased size
      height: 240, // Increased size
      child: CustomPaint(
        painter: _RingPainter(
          completed: completedPercent,
          missed: missedPercent,
          partial: partialPercent,
          completedColor: completedColor,
          missedColor: missedColor,
          partialColor: partialColor,
        ),
        child: Center(
          child: Text(
            '$percentage%',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      ),
    );
  }
}

// Custom painter to draw the segmented ring
class _RingPainter extends CustomPainter {
  final double completed;
  final double missed;
  final double partial;
  final Color completedColor;
  final Color missedColor;
  final Color partialColor;
  final double strokeWidth;

  _RingPainter({
    required this.completed,
    required this.missed,
    required this.partial,
    required this.completedColor,
    required this.missedColor,
    required this.partialColor,
    this.strokeWidth = 22.0, // Increased thickness
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = -pi / 2; // Start from the top

    // Background ring
    final backgroundPaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, backgroundPaint);

    // Define paints for each status
    final completedPaint = Paint()
      ..color = completedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final missedPaint = Paint()
      ..color = missedColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final partialPaint = Paint()
      ..color = partialColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Calculate sweep angles
    const fullCircle = 2 * pi;
    final double completedSweep = completed * fullCircle;
    final double missedSweep = missed * fullCircle;
    final double partialSweep = partial * fullCircle;

    // Draw arcs
    double currentStartAngle = startAngle;

    if (completed > 0) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          currentStartAngle, completedSweep, false, completedPaint);
    }
    currentStartAngle += completedSweep;

    if (missed > 0) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          currentStartAngle, missedSweep, false, missedPaint);
    }
    currentStartAngle += missedSweep;

    if (partial > 0) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          currentStartAngle, partialSweep, false, partialPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.completed != oldDelegate.completed ||
        oldDelegate.missed != missed ||
        oldDelegate.partial != partial;
  }
}