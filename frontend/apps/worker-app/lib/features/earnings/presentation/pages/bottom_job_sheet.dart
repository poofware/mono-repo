// worker-app/lib/features/earnings/presentation/pages/bottom_job_sheet.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations

/// A bottom sheet shown for a *completed* job, adapted to use [JobInstance].
/// This is just a placeholder for demonstration, preserving the old UI style
/// while using the new `jobInstance` data.
class CompletedJobBottomSheet extends StatelessWidget {
  final JobInstance jobInstance;

  const CompletedJobBottomSheet({super.key, required this.jobInstance});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    // For demonstration, treat serviceDate as the "completed" date:
    final completedDate = _parseServiceDate(jobInstance.serviceDate);
    final completedDateStr = DateFormat('MMM d, yyyy h:mm a').format( // TODO: Localize date/time format if needed
      completedDate.add(const Duration(hours: 9)), // example offset
    );

    // Placeholder for how long it took
    final duration = const Duration(minutes: 42);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final timeStr = '${h.toString().padLeft(2, '0')}h ${m.toString().padLeft(2, '0')}m';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        // so the sheet only wraps its content
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Optional drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            appLocalizations.completedJobBottomSheetTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          Text(appLocalizations.completedJobBottomSheetPropertyLabel(jobInstance.property.propertyName)),
          Text(appLocalizations.completedJobBottomSheetAddressLabel(jobInstance.property.address)),
          Text(appLocalizations.completedJobBottomSheetPayLabel(jobInstance.pay.toStringAsFixed(2))),
          Text(appLocalizations.completedJobBottomSheetCompletedLabel(completedDateStr)),
          Text(appLocalizations.completedJobBottomSheetTimeToCompleteLabel(timeStr)),
          const SizedBox(height: 8),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(appLocalizations.completedJobBottomSheetCloseButton),
            ),
          ),
        ],
      ),
    );
  }

  DateTime _parseServiceDate(String dateStr) {
    // "YYYY-MM-DD"
    final parts = dateStr.split('-');
    if (parts.length < 3) return DateTime(1970, 1, 1);
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    return DateTime(y, m, d);
  }
}

