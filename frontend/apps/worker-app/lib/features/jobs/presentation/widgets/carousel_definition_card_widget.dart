// worker-app/lib/features/jobs/presentation/widgets/carousel_definition_card_widget.dart

import 'package:flutter/material.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import '../../data/models/job_models.dart';
import 'info_widgets.dart';
import 'job_accept_sheet.dart';

/// Horizontally-scrolled carousel card (DefinitionGroup), with building info.
/// Drive distance and estimated time have been removed. Start time hint added.
/// Info items in a single row, symmetrically spaced.
class CarouselDefinitionCard extends StatelessWidget {
  final DefinitionGroup definition;

  const CarouselDefinitionCard({super.key, required this.definition});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    final cardColor = Theme.of(context).canvasColor;
    final avgPayLabel =
        '\$${definition.pay.toStringAsFixed(0)} ${appLocalizations.definitionCardAvgSuffix}';
    final representativeInstance =
        definition.instances.isNotEmpty ? definition.instances.first : null;
    final bool hasBuildingInfo = definition.instances.isNotEmpty &&
        definition.instances.any((inst) => inst.numberOfBuildings > 0);

    return InkWell(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.0),
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
      child: SizedBox(
        width: double.infinity,
        child: Card(
          color: cardColor,
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top section: name + subtitle + avg pay
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
                                fontSize: 16, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          if (definition.buildingSubtitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2.0),
                              child: Text(
                                definition.buildingSubtitle,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey.shade600,
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
                      avgPayLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Middle section: address
                Text(
                  definition.propertyAddress,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 8),
                // Bottom section: icons and info (single row) with fixed-width cells
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
                              workerTimeHint: representativeInstance
                                      ?.workerStartTimeHint ??
                                  '',
                              propertyTimeHint:
                                  representativeInstance?.startTimeHint ?? '',
                            ),
                          ),
                        ),

                        // Second cell: BuildingInfo (centered) or empty if none
                        SizedBox(
                          width: cellWidth,
                          child: hasBuildingInfo
                              ? Align(
                                  alignment: Alignment.center,
                                  child: BuildingInfo(
                                    instances: definition.instances,
                                  ),
                                )
                              : const SizedBox.shrink(),
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
      ),
    );
  }
}
