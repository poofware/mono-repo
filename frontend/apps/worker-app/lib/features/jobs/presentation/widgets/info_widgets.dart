import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import '../../data/models/job_models.dart';

/// Fixed width used by info-rows that need their icon to align perfectly
/// in a vertical list. 88 px is wide enough for strings like “1 hr 45 min”
/// in most locales while keeping the footprint tight.
const double _kInfoRowWidth = 88;

/// A shared utility to format a 24-hour time string (e.g., "15:30")
/// into a 12-hour AM/PM format (e.g., "3:30 PM").
String formatTime(BuildContext context, String timeHint24Hour) {
  if (timeHint24Hour.isEmpty) return '';
  try {
    final parts = timeHint24Hour.split(':');
    if (parts.length != 2) return timeHint24Hour; // malformed

    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    final now = DateTime.now();
    final dateTime = DateTime(now.year, now.month, now.day, hour, minute);
    return DateFormat.jm().format(dateTime); // e.g., "8:00 AM"
  } catch (_) {
    return timeHint24Hour; // fallback
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TimeInfo
// ─────────────────────────────────────────────────────────────────────────────

class TimeInfo extends StatelessWidget {
  final String displayTime;

  const TimeInfo({super.key, required this.displayTime});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kInfoRowWidth,
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 16),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              displayTime,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DriveTimeInfo  ⇢  RIGHT-HAND COLUMN (icon must line up across cards)
// ─────────────────────────────────────────────────────────────────────────────

class DriveTimeInfo extends StatelessWidget {
  final String travelTime;

  const DriveTimeInfo({super.key, required this.travelTime});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kInfoRowWidth,
      child: Row(
        children: [
          const Icon(Icons.directions_car_outlined, size: 16),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              travelTime,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VehicleInfo
// ─────────────────────────────────────────────────────────────────────────────

class VehicleInfo extends StatelessWidget {
  final TransportMode transportMode;

  const VehicleInfo({super.key, required this.transportMode});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final icon = transportMode == TransportMode.car
        ? Icons.directions_car
        : Icons.directions_walk;
    final label = transportMode == TransportMode.car
        ? appLocalizations.transportModeCar
        : appLocalizations.transportModeWalk;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BuildingInfo  ⇢  CENTRE COLUMN (width is flexible)
// ─────────────────────────────────────────────────────────────────────────────

class BuildingInfo extends StatelessWidget {
  final List<JobInstance> instances;

  const BuildingInfo({super.key, required this.instances});

  @override
  Widget build(BuildContext context) {
    if (instances.isEmpty) return const SizedBox.shrink();
    final counts = instances
        .map((i) => i.numberOfBuildings)
        .where((c) => c > 0);
    if (counts.isEmpty) return const SizedBox.shrink();

    final minCount = counts.reduce(min);
    final maxCount = counts.reduce(max);
    final label = minCount == maxCount
        ? '$minCount bldg${minCount > 1 ? 's' : ''}'
        : '$minCount-$maxCount bldgs';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.apartment_outlined, size: 16),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// FloorInfo  ⇢  CENTRE COLUMN (width is flexible)
// ─────────────────────────────────────────────────────────────────────────────

class FloorInfo extends StatelessWidget {
  final List<JobInstance> instances;

  const FloorInfo({super.key, required this.instances});

  @override
  Widget build(BuildContext context) {
    if (instances.isEmpty) return const SizedBox.shrink();

    final allFloors = instances
        .expand((i) => i.buildings)
        .expand((b) => b.floors)
        .toList();

    if (allFloors.isEmpty) return const SizedBox.shrink();

    final uniqueFloors = allFloors.toSet().toList();
    uniqueFloors.sort();

    String label;
    if (uniqueFloors.length > 2) {
      label = '${uniqueFloors.length} floors';
    } else {
      label = 'fl ${uniqueFloors.join(', ')}';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.stairs_outlined, size: 16),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StartTimeHintInfo  ⇢  LEFT-HAND COLUMN (kept flexible)
// ─────────────────────────────────────────────────────────────────────────────

class StartTimeHintInfo extends StatelessWidget {
  final String workerTimeHint;
  final String propertyTimeHint;

  const StartTimeHintInfo({
    super.key,
    required this.workerTimeHint,
    required this.propertyTimeHint,
  });

  @override
  Widget build(BuildContext context) {
    final formattedWorkerTime = formatTime(context, workerTimeHint);
    if (formattedWorkerTime.isEmpty) return const SizedBox.shrink();

    final showPropertyTime =
        propertyTimeHint.isNotEmpty && workerTimeHint != propertyTimeHint;
    final formattedPropertyTime = showPropertyTime
        ? formatTime(context, propertyTimeHint)
        : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.access_time_outlined, size: 16),
        const SizedBox(width: 3),
        Flexible(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
              children: [
                TextSpan(text: formattedWorkerTime),
                if (showPropertyTime)
                  TextSpan(
                    text: ' ($formattedPropertyTime)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
