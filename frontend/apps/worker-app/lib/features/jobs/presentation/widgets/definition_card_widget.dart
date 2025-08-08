// worker-app/lib/features/jobs/presentation/widgets/definition_card_widget.dart

import 'package:flutter/material.dart';
import '../../data/models/job_models.dart';
import 'info_widgets.dart';
import 'job_accept_sheet.dart'; // Import the new sheet
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations

/// Displays an "Available Job" card (single DefinitionGroup).
/// Shows average pay, drive time, building count, and start time hint.
/// Drive distance and estimated time have been removed. Info items are in a single row, symmetrically spaced.
/// Includes a button to "View on Map".
class DefinitionCard extends StatelessWidget {
  final DefinitionGroup definition;
  final VoidCallback? onViewOnMapPressed; // Callback for the "View on Map" button

  const DefinitionCard({
    super.key,
    required this.definition,
    this.onViewOnMapPressed,
  });

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final color = Theme.of(context).canvasColor;
    final avgPayLabel =
        '\$${definition.pay.toStringAsFixed(0)} ${appLocalizations.definitionCardAvgSuffix}';
    final representativeInstance =
        definition.instances.isNotEmpty ? definition.instances.first : null;
    final bool hasBuildingInfo = definition.instances.isNotEmpty &&
        definition.instances.any((inst) => inst.numberOfBuildings > 0);
    final bool isSingleBuilding = definition.instances.isNotEmpty &&
        definition.instances.every((inst) => inst.numberOfBuildings == 1);

    return InkWell(
      onTap: () {
        // Show the new JobAcceptSheet as a modal bottom sheet
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor:
              Colors.transparent, // Sheet container will have its own color
          barrierColor:
              Colors.black.withValues(alpha: 0.0), // Transparent barrier
          builder: (BuildContext context) {
            // By wrapping the sheet in its own Scaffold, ScaffoldMessenger.of(context)
            // inside the sheet will find this Scaffold first, and the SnackBar will
            // appear correctly on top of the sheet.
            return Scaffold(
              backgroundColor: Colors.transparent, // Keeps the modal transparent look
              body: Align(
                alignment: Alignment.bottomCenter,
                child: JobAcceptSheet(definition: definition),
              ),
            );
          },
        );
      },
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Card(
        color: color,
        elevation: 5,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Property Info | Pay & Map Button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          definition.propertyName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                        if (definition.buildingSubtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              definition.buildingSubtitle,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(
                            definition.propertyAddress,
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade700),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        avgPayLabel,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      // Conditional View on Map Button
                      if (onViewOnMapPressed != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: IconButton(
                            icon: const Icon(Icons.map_outlined),
                            tooltip:
                                appLocalizations.definitionCardViewOnMapTooltip,
                            onPressed: onViewOnMapPressed,
                            color: Theme.of(context).primaryColor,
                            iconSize: 24,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 36, minHeight: 36),
                            splashRadius: 20,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Row 2: Info Icons (single row) with fixed-width cells
              LayoutBuilder(
                builder: (context, constraints) {
                  // Divide the available width (inside the padding) into 3 equal slices
                  final cellWidth = constraints.maxWidth / 3;

                  return Row(
                    children: [
                      // First cell: StartTimeHintInfo (left-aligned)
                      SizedBox(
                        width: cellWidth,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: StartTimeHintInfo(
                            workerTimeHint:
                                representativeInstance?.workerStartTimeHint ??
                                    '',
                            propertyTimeHint:
                                representativeInstance?.startTimeHint ?? '',
                          ),
                        ),
                      ),

                      // Second cell: BuildingInfo or FloorInfo (centered)
                      SizedBox(
                        width: cellWidth,
                        child: Align(
                          alignment: Alignment.center,
                          child: isSingleBuilding
                              ? FloorInfo(instances: definition.instances)
                              : hasBuildingInfo
                                  ? BuildingInfo(instances: definition.instances)
                                  : const SizedBox.shrink(),
                        ),
                      ),

                      // Third cell: DriveTimeInfo (right-aligned)
                      SizedBox(
                        width: cellWidth,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: DriveTimeInfo(
                            travelTime: definition.displayAvgTravelTime,
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
