import 'package:flutter/material.dart';
import '../../data/models/job_models.dart';
import 'info_widgets.dart';

class AcceptedJobCard extends StatelessWidget {
  final JobInstance job;
  final VoidCallback? onTap;

  const AcceptedJobCard({
    super.key,
    required this.job,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color cardColor = Theme.of(context).canvasColor;

    return InkWell(
      onTap: onTap,
      child: Card(
        color: cardColor,
        elevation: 5,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // top row: propertyName + pay
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.property.propertyName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                        if (job.buildingSubtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              job.buildingSubtitle,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '\$${job.pay.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // address
              Text(
                job.property.address,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 12),
              // Info Row – wrapped in LayoutBuilder so we can evenly split width
              LayoutBuilder(
                builder: (context, constraints) {
                  // Divide the available width (inside the padding) into 3 equal slices.
                  final cellWidth = constraints.maxWidth / 3;

                  return Row(
                    children: [
                      // 1st cell: StartTimeHintInfo
                      SizedBox(
                        width: cellWidth,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StartTimeHintInfo(
                            workerTimeHint: job.workerStartTimeHint,
                            propertyTimeHint: job.startTimeHint,
                          ),
                        ),
                      ),

                      // 2nd cell: BuildingInfo or FloorInfo (centered)
                      SizedBox(
                        width: cellWidth,
                        child: Align(
                          alignment: Alignment.center,
                          child: (job.numberOfBuildings == 1)
                              ? FloorInfo(instances: [job])
                              : BuildingInfo(instances: [job]),
                        ),
                      ),

                      // 3rd cell: DriveTimeInfo (right-aligned within a fixed cell)
                      SizedBox(
                        width: cellWidth,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: DriveTimeInfo(
                            travelTime: job.displayTravelTime,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
