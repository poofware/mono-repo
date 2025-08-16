// worker-app/lib/features/jobs/presentation/widgets/job_accept_sheet.dart
// worker-app/lib/features/jobs/presentation/widgets/job_accept_sheet.dart
//
// UI refresh: modern card header, aggregated stats.
// Adapted to be shown in a modal bottom sheet.
// Includes comprehensive details for selected instance, improved UI, and fixed accept button.
// Pay icon restored, dollar sign removed from text value, "USD" unit added. Start time formatted to AM/PM.
// Accept button has more bottom padding.
// No job instance is auto-selected on open; user must tap a day on the carousel.
// Sheet height animates when an instance is selected. Header stats are now in a single row, evenly spaced.
// Carousel will not pre-highlight a day if no instance is selected.
// Refined AnimatedSwitcher to reduce flicker.
// Added full sheet dimming and loading indicator during job acceptance.
// Sheet now closes only if the accepted job was the last available instance in the group.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';
import 'package:poof_worker/features/jobs/presentation/widgets/date_carousel_widget.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';
import 'info_widgets.dart';
import 'job_map_cache.dart';
import 'view_job_map_button.dart';

class JobAcceptSheet extends ConsumerStatefulWidget {
  final DefinitionGroup definition;

  const JobAcceptSheet({super.key, required this.definition});

  @override
  ConsumerState<JobAcceptSheet> createState() => _JobAcceptSheetState();
}

class _JobAcceptSheetState extends ConsumerState<JobAcceptSheet> {
  late DateTime _carouselInitialDate;
  JobInstance? _selectedInstance;
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _carouselInitialDate = DateTime(now.year, now.month, now.day);
    // Cancel any pending eviction for the representative instance on open.
    if (widget.definition.instances.isNotEmpty) {
      final rep = widget.definition.instances.first;
      JobMapCache.cancelEvict(rep.instanceId);
    }
  }

  @override
  void dispose() {
    // Schedule eviction on close for representative instance, matching accepted sheet.
    if (widget.definition.instances.isNotEmpty) {
      final rep = widget.definition.instances.first;
      JobMapCache.scheduleEvict(rep.instanceId);
    }
    super.dispose();
  }

  void _updateSelectedInstance(DateTime day) {
    final match = widget.definition.instances.where(
      (inst) => _isSameDate(parseYmd(inst.serviceDate), day),
    );
    _selectedInstance = match.isEmpty ? null : match.first;
  }

  void _handleDateSelected(DateTime day) {
    setState(() {
      _carouselInitialDate = day;
      _updateSelectedInstance(day);
    });
  }

  Future<void> _acceptSelectedInstance() async {
    if (_selectedInstance == null || _isAccepting) return;

    // --- Capture context-sensitive objects BEFORE async gaps ---
    final navigator = Navigator.of(context);
    final logger = ref.read(appLoggerProvider);

    // --- Check if this is the last instance in the current group ---
    final currentOpenJobsBeforeAccept = ref.read(jobsNotifierProvider).openJobs;
    final currentDefinitionGroupsBeforeAccept = groupOpenJobs(
      currentOpenJobsBeforeAccept,
    );
    final liveDefinitionBeforeAccept = currentDefinitionGroupsBeforeAccept
        .firstWhere(
          (dg) => dg.definitionId == widget.definition.definitionId,
          orElse: () => widget
              .definition, // Fallback, though should ideally always find it
        );
    final bool wasLastInstanceInGroup =
        liveDefinitionBeforeAccept.instances.length == 1 &&
        liveDefinitionBeforeAccept.instances.first.instanceId ==
            _selectedInstance!.instanceId;
    // ---

    setState(() => _isAccepting = true);
    logger.d(
      'User initiated accept for instance: ${_selectedInstance!.instanceId}',
    );

    // The notifier now returns a boolean. The GlobalErrorListener handles failure snackbars.
    final bool wasSuccess = await ref
        .read(jobsNotifierProvider.notifier)
        .acceptJob(_selectedInstance!.instanceId);

    // This block now runs regardless of success or failure.
    if (mounted) {
      setState(() => _isAccepting = false);
    } else {
      // If the widget is unmounted, we can't do anything else.
      return;
    }

    if (wasSuccess) {
      logger.i(
        'Instance ${_selectedInstance!.instanceId} accepted successfully via notifier.',
      );

      // Check state *after* acceptance
      final currentOpenJobsAfterAccept = ref
          .read(jobsNotifierProvider)
          .openJobs;
      final currentDefinitionGroupsAfterAccept = groupOpenJobs(
        currentOpenJobsAfterAccept,
      );

      final definitionGroupStillExists = currentDefinitionGroupsAfterAccept.any(
        (group) => group.definitionId == widget.definition.definitionId,
      );

      bool shouldCloseSheet = false;
      if (wasLastInstanceInGroup) {
        // If it was the last instance, the group should now be empty or gone.
        if (!definitionGroupStillExists) {
          shouldCloseSheet = true;
        } else {
          // Check if the group still exists but its instances list is now empty
          final updatedGroup = currentDefinitionGroupsAfterAccept.firstWhere(
            (group) => group.definitionId == widget.definition.definitionId,
          );
          if (updatedGroup.instances.isEmpty) {
            shouldCloseSheet = true;
          }
        }
      }

      if (shouldCloseSheet) {
        if (mounted) {
          logger.d('Accepted the last instance, closing sheet.');
          navigator.pop();
        }
      } else {
        // If the group still exists but the specific accepted instance is gone, clear selection
        final liveDefinitionAfterAccept = currentDefinitionGroupsAfterAccept
            .firstWhere(
              (dg) => dg.definitionId == widget.definition.definitionId,
              orElse: () => DefinitionGroup(
                definitionId: '',
                propertyName: '',
                propertyAddress: '',
                distanceMiles: 0,
                pay: 0,
                transportMode: TransportMode.walk,
                instances: [],
              ), // Dummy if group disappeared unexpectedly
            );
        if (!liveDefinitionAfterAccept.instances.any(
          (inst) => inst.instanceId == _selectedInstance?.instanceId,
        )) {
          if (mounted) {
            setState(() {
              _selectedInstance = null;
            });
          }
        }
      }
    }
    // No 'else' block needed, as the GlobalErrorListener handles failure UI.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final screenHeight = MediaQuery.of(context).size.height;
    final appLocalizations = AppLocalizations.of(context);
    final mediaQueryPadding = MediaQuery.of(context).padding;
    // Revert: remove dynamic bottom gap behavior

    final currentOpenJobs = ref.watch(
      jobsNotifierProvider.select((s) => s.openJobs),
    );
    final currentDefinitionGroups = groupOpenJobs(currentOpenJobs);
    final liveDefinition = currentDefinitionGroups.firstWhere(
      (dg) => dg.definitionId == widget.definition.definitionId,
      orElse: () => widget.definition,
    );

    final isCarouselDateActuallySelected =
        _selectedInstance != null &&
        liveDefinition.instances.any(
          (inst) =>
              inst.instanceId == _selectedInstance!.instanceId &&
              _isSameDate(parseYmd(inst.serviceDate), _carouselInitialDate),
        );

    // Note: Buildings and units info now always visible

    // Determine dates for carousel.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.add(const Duration(days: -1));

    // Check if any job in this definition group is for yesterday.
    final bool hasJobYesterday = liveDefinition.instances.any(
      (inst) => _isSameDate(parseYmd(inst.serviceDate), yesterday),
    );

    // The carousel starts from yesterday if there's a job on that day, otherwise today.
    final DateTime carouselStartDate = hasJobYesterday ? yesterday : today;

    // Find the latest instance date for this group to ensure the carousel extends far enough.
    DateTime latestInstanceDate = today;
    if (liveDefinition.instances.isNotEmpty) {
      latestInstanceDate = liveDefinition.instances
          .map((inst) => parseYmd(inst.serviceDate))
          .reduce((a, b) => a.isAfter(b) ? a : b);
    }

    // Default end date is 7 days from today.
    final defaultEndDate = today.add(const Duration(days: 7));
    final carouselEndDate = latestInstanceDate.isAfter(defaultEndDate)
        ? latestInstanceDate
        : defaultEndDate;

    // Calculate total days from the dynamic start date to the calculated end date.
    final dayCount = carouselEndDate.difference(carouselStartDate).inDays + 1;
    final carouselDates = List.generate(
      dayCount,
      (i) => carouselStartDate.add(Duration(days: i)),
    );

    // Sheet height constraint (original behavior)
    final double maxSheetHeight = screenHeight * 0.95;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(38),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header / Drag Handle
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // This flexible + scroll view holds all content EXCEPT the bottom button.
            // It will only scroll if the content inside exceeds the space given to it
            // by the parent Column, which is constrained by the ConstrainedBox.
            Flexible(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  // Background tap clears selection when a date is selected
                  if (_selectedInstance != null) {
                    setState(() {
                      _selectedInstance = null;
                    });
                  }
                },
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header card and stats with standard horizontal padding
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GestureDetector(
                          onTap: () {}, // swallow taps on the card body
                          child: Card(
                            color: cardColor,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                10, // slightly tighter bottom padding to reduce gap to carousel
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTap: () {
                                      if (_selectedInstance != null) {
                                        setState(() {
                                          _selectedInstance = null;
                                        });
                                      }
                                    },
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          liveDefinition.propertyName,
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          liveDefinition.propertyAddress,
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Compact definition-level tiles (no dividing line)
                                  const SizedBox(height: 12),
                                  _DefinitionStatTiles(
                                    definition: liveDefinition,
                                    appLocalizations: appLocalizations,
                                    showAvgPay: _selectedInstance == null,
                                    showAvgTime: _selectedInstance == null,
                                  ),
                                  const SizedBox(height: 12),
                                  ViewJobMapButton(
                                    job: liveDefinition.instances.isNotEmpty
                                        ? liveDefinition.instances.first
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Date carousel should go edge-to-edge (no horizontal padding)
                      Padding(
                        // Consistent spacing after buildings/units info
                        padding: const EdgeInsets.only(top: 8),
                        child: DateCarousel(
                          availableDates: carouselDates,
                          selectedDate: isCarouselDateActuallySelected
                              ? _carouselInitialDate
                              : DateTime(0),
                          onDateSelected: _handleDateSelected,
                          isDayEnabled: (day) => liveDefinition.instances.any(
                            (inst) => _isSameDate(parseYmd(inst.serviceDate), day),
                          ),
                          leftPadding: 14.0,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Post-carousel content with horizontal padding restored
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: (_selectedInstance == null ||
                                !liveDefinition.instances.any(
                                  (i) => i.instanceId == _selectedInstance!.instanceId,
                                ))
                            ? Container(
                                key: const ValueKey('no_instance_selected_or_accepted'),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(vertical: 20),
                                child: Text(
                                  appLocalizations.jobAcceptSheetSelectDayPrompt,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : _InstanceDetails(
                                key: ValueKey(_selectedInstance!.instanceId),
                                instance: _selectedInstance!,
                                appLocalizations: appLocalizations,
                              ),
                      ),
                      if (_selectedInstance != null)
                        const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),

            // Sticky button at the bottom
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                mediaQueryPadding.bottom + 16.0,
              ),
              child: WelcomeButton(
                text: _isAccepting
                    ? appLocalizations.jobAcceptSheetAcceptingButton
                    : appLocalizations.jobAcceptSheetAcceptButton,
                isLoading: _isAccepting,
                onPressed:
                    (_selectedInstance == null ||
                        !liveDefinition.instances.any(
                          (i) => i.instanceId == _selectedInstance!.instanceId,
                        ))
                    ? null
                    : _acceptSelectedInstance,
              ),
            ),
          ],
          ),
        ),
    );
  }


}

class _InstanceDetails extends StatelessWidget {
  final JobInstance instance;
  final AppLocalizations appLocalizations;

  const _InstanceDetails({
    super.key,
    required this.instance,
    required this.appLocalizations,
  });

  @override
  Widget build(BuildContext context) {
    final payLabel = appLocalizations.acceptedJobsBottomSheetPayLabel;
    final estTimeLabel = appLocalizations.jobAcceptSheetHeaderAvgCompletion;
    return GestureDetector(
      onTap: () {},
      child: Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _TwoColumnTiles(tiles: [
            _TileData(
              icon: Icons.attach_money,
              label: payLabel,
              value: '${instance.pay.toStringAsFixed(0)} USD',
              color: Colors.green,
            ),
            _TileData(
              icon: Icons.timer_outlined,
              label: estTimeLabel,
              value: instance.displayTime,
            ),
            // Definition-level stats omitted here to avoid redundancy
            // Consolidated: Remove definition-level items from instance tiles
          ]),
        ),
      ),
    );
  }

  // (removed) unused helper
}

// Definition-level compact stats (base state)
class _DefinitionStatTiles extends StatelessWidget {
  final DefinitionGroup definition;
  final AppLocalizations appLocalizations;
  final bool showAvgPay;
  final bool showAvgTime;
  const _DefinitionStatTiles({
    required this.definition,
    required this.appLocalizations,
    this.showAvgPay = true,
    this.showAvgTime = true,
  });
  @override
  Widget build(BuildContext context) {
    final inst = definition.instances.isNotEmpty ? definition.instances.first : null;
    final start = inst?.workerStartTimeHint ?? '';
    final startFormatted = start.isNotEmpty ? formatTime(context, start) : '';
    final workerWindowStart = inst?.workerServiceWindowStart ?? '';
    final workerWindowEnd = inst?.workerServiceWindowEnd ?? '';
    final windowDisplay = (workerWindowStart.isNotEmpty && workerWindowEnd.isNotEmpty)
        ? '${formatTime(context, workerWindowStart)} - ${formatTime(context, workerWindowEnd)}'
        : '';
    final bool isSingleBuilding = definition.instances.isNotEmpty &&
        definition.instances.every((i) => i.numberOfBuildings == 1);
    final tiles = <_TileData>[
      if (showAvgPay)
        _TileData(
          icon: Icons.attach_money,
          label: 'Avg Pay',
          value: '${definition.pay.toStringAsFixed(0)} USD',
          color: Colors.green,
        ),
      if (showAvgTime)
        _TileData(
          icon: Icons.timer_outlined,
          label: appLocalizations.jobAcceptSheetHeaderAvgCompletion,
          value: definition.displayAvgTime,
        ),
      _TileData(
        icon: Icons.directions_car_outlined,
        label: appLocalizations.jobAcceptSheetHeaderDriveTime,
        value: definition.displayAvgTravelTime,
      ),
      if (startFormatted.isNotEmpty)
        _TileData(
          icon: Icons.access_time_outlined,
          label: appLocalizations.jobAcceptSheetRecommendedStart,
          value: startFormatted,
        ),
      if (windowDisplay.isNotEmpty)
        _TileData(
          icon: Icons.hourglass_empty_outlined,
          label: appLocalizations.jobAcceptSheetServiceWindow,
          value: windowDisplay,
          spanTwoColumns: true,
        ),
      _TileData(
        icon: Icons.apartment_outlined,
        label: appLocalizations.jobAcceptSheetBuildings,
        value: _buildBuildingsLabel(definition.instances),
      ),
      if (isSingleBuilding)
        _TileData(
          icon: Icons.stairs_outlined,
          label: appLocalizations.jobAcceptSheetFloors,
          value: _buildFloorsLabel(definition.instances),
        ),
      _TileData(
        icon: Icons.home_outlined,
        label: appLocalizations.jobAcceptSheetUnits,
        value: _buildUnitsLabel(definition.instances),
      ),
    ];
    return _TwoColumnTiles(tiles: tiles);
  }
}

// (removed) Replaced with shared ViewJobMapButton

String _buildBuildingsLabel(List<JobInstance> instances) {
  if (instances.isEmpty) return '—';
  final counts = instances.map((i) => i.numberOfBuildings).where((c) => c > 0);
  if (counts.isEmpty) return '—';
  final minCount = counts.reduce((a, b) => a < b ? a : b);
  final maxCount = counts.reduce((a, b) => a > b ? a : b);
  if (minCount == maxCount) {
    final plural = minCount == 1 ? '' : 's';
    return '$minCount bldg$plural';
  }
  return '$minCount-$maxCount bldgs';
}

String _buildFloorsLabel(List<JobInstance> instances) {
  if (instances.isEmpty) return '—';
  final allFloors = instances.expand((i) => i.buildings).expand((b) => b.floors);
  final unique = allFloors.toSet().toList()..sort();
  if (unique.isEmpty) return '—';
  if (unique.length > 2) return '${unique.length} floors';
  return 'fl ${unique.join(', ')}';
}

String _buildUnitsLabel(List<JobInstance> instances) {
  if (instances.isEmpty) return '—';
  // Use the first instance's label as representative
  return instances.first.totalUnitsLabel;
}

// Generic tile data
class _TileData {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final bool spanTwoColumns;
  _TileData({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.spanTwoColumns = false,
  });
}

// Two-column responsive tile wrapper
class _TwoColumnTiles extends StatelessWidget {
  final List<_TileData> tiles;
  const _TwoColumnTiles({required this.tiles});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const spacing = 10.0;
      final isNarrow = constraints.maxWidth < 360;
      final columns = isNarrow ? 1 : 2;
      final itemWidth =
          columns == 1 ? constraints.maxWidth : (constraints.maxWidth - spacing) / 2;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: tiles.map((t) {
          final double width =
              columns == 2 && t.spanTwoColumns ? constraints.maxWidth : itemWidth;
          return SizedBox(
            width: width,
            child: _StatTile(
              icon: t.icon,
              label: t.label,
              value: t.value,
              color: t.color,
            ),
          );
        }).toList(),
      );
    });
  }
}

// Single stat tile
class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = color ?? Colors.black87;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: baseColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: baseColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// (removed) previously used time info tile; unified into generic tiles

DateTime parseYmd(String ymd) {
  final parts = ymd.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

extension NullableObjectExt<T> on T {
  R let<R>(R Function(T it) op) => op(this);
}
