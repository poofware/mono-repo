import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:poof_pm/features/jobs/data/models/job_instance_pm.dart';
import 'package:poof_pm/features/jobs/data/models/job_status.dart';

class JobHistoryTimeline extends StatelessWidget {
  const JobHistoryTimeline({super.key, required this.entries});

  final List<JobInstancePm> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('No jobs found.'));
    }

    final Map<DateTime, List<JobInstancePm>> grouped = {};
    for (final e in entries) {
      final key = DateTime.parse(e.serviceDate);
      final dayOnly = DateTime(key.year, key.month, key.day);
      grouped.putIfAbsent(dayOnly, () => []).add(e);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemCount: days.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final day = days[index];
        final jobs = grouped[day]!;
        return _DaySection(date: day, jobs: jobs);
      },
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.date, required this.jobs});

  final DateTime date;
  final List<JobInstancePm> jobs;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy').format(date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          ...jobs.map((j) => _JobRow(entry: j)).toList(),
          if (jobs.isNotEmpty) const SizedBox(height: 8),
          const Divider(height: 1, thickness: 1),
        ],
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.entry});
  final JobInstancePm entry;

  @override
  Widget build(BuildContext context) {
    final ui = StatusUI.from(jobStatusFromString(entry.status));

    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Job #${entry.instanceId.substring(0, 8)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
          ),
          const Spacer(),
          Container(
            width: 115,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: ui.bg,
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(ui.icon, size: 15, color: ui.textColor),
                const SizedBox(width: 6),
                Text(
                  ui.text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: ui.textColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}