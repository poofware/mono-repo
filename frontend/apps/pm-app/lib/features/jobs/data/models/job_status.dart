import 'package:flutter/material.dart';

enum JobStatus {
  completed,
  missed,
  upcoming,
  partiallyCompleted,
  unknown,
}

String jobStatusToString(JobStatus status) {
  switch (status) {
    case JobStatus.completed:
      return 'Completed';
    case JobStatus.missed:
      return 'Missed';
    case JobStatus.upcoming:
      return 'Upcoming';
    case JobStatus.partiallyCompleted:
      return 'Partially Completed';
    default:
      return 'Unknown';
  }
}

JobStatus jobStatusFromString(String? statusStr) {
  switch (statusStr?.toLowerCase().replaceAll(' ', '')) {
    // These should match the values from your Go `InstanceStatusType`
    case 'completed':
      return JobStatus.completed;
    case 'missed':
    case 'retired': // Map 'retired' to 'missed' for UI purposes
    case 'canceled': // Map 'canceled' to 'missed' for UI purposes
      return JobStatus.missed;
    case 'inprogress': // Example if you want to show in-progress as partial
      return JobStatus.partiallyCompleted;
    case 'assigned':
    case 'open':
      return JobStatus.upcoming; // Or a new status like 'upcoming'
    default:
      return JobStatus.unknown;
  }
}

/// A helper class to map a JobStatus to its corresponding UI elements.
class StatusUI {
  const StatusUI(this.icon, this.text, this.bg, this.textColor);
  final IconData icon;
  final String text;
  final Color bg;
  final Color textColor;

  factory StatusUI.from(JobStatus s) {
    switch (s) {
      case JobStatus.completed:
        // CHANGED: Use a bold green color, with white text.
        return const StatusUI(Icons.check_circle, 'Completed', Color(0xFF388E3C), Colors.white);
      case JobStatus.missed:
        // Use a bold red color, with white text.
        return const StatusUI(Icons.cancel, 'Missed', Color(0xFFD32F2F), Colors.white);
      case JobStatus.partiallyCompleted:
        // CHANGED: Use a bold, more yellow-orange (amber), with white text.
        return const StatusUI(Icons.hourglass_top, 'Partial', Color(0xFFFFA000), Colors.white);
      case JobStatus.upcoming:
        // Use a bold blue color, with white text.
        return const StatusUI(Icons.schedule, 'Upcoming', Color(0xFF1976D2), Colors.white);
      case JobStatus.unknown:
      default:
        return StatusUI(Icons.help_outline, 'Unknown', Colors.grey.shade300, Colors.black54);
    }
  }
}