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
        logger.d('Accepted the last instance, closing sheet.');
        navigator.pop();
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
          setState(() {
            _selectedInstance = null;
          });
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

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
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
          mainAxisSize:
              MainAxisSize.min, // This is key: column shrinks to fit children
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
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Card, Carousel, and Details are here
                      Card(
                        color: cardColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
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
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  Expanded(
                                    child: _statTile(
                                      icon: Icons.attach_money,
                                      label: appLocalizations
                                          .jobAcceptSheetHeaderAvgPay,
                                      value:
                                          '${liveDefinition.pay.toStringAsFixed(0)} USD',
                                    ),
                                  ),
                                  Expanded(
                                    child: _statTile(
                                      icon: Icons.timer_outlined,
                                      label: appLocalizations
                                          .jobAcceptSheetHeaderAvgTime,
                                      value: liveDefinition.displayAvgTime,
                                    ),
                                  ),
                                  Expanded(
                                    child: _statTile(
                                      icon: Icons.directions_car_outlined,
                                      label: appLocalizations
                                          .jobAcceptSheetHeaderDriveTime,
                                      value:
                                          liveDefinition.displayAvgTravelTime,
                                    ),
                                  ),
                                  Expanded(
                                    child: _statTile(
                                      icon: Icons.location_on_outlined,
                                      label: appLocalizations
                                          .jobAcceptSheetHeaderDistance,
                                      value:
                                          '${liveDefinition.distanceMiles.toStringAsFixed(1)} mi',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      DateCarousel(
                        availableDates: carouselDates,
                        selectedDate: isCarouselDateActuallySelected
                            ? _carouselInitialDate
                            : DateTime(0),
                        onDateSelected: _handleDateSelected,
                        isDayEnabled: (day) => liveDefinition.instances.any(
                          (inst) =>
                              _isSameDate(parseYmd(inst.serviceDate), day),
                        ),
                      ),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                        child:
                            (_selectedInstance == null ||
                                !liveDefinition.instances.any(
                                  (i) =>
                                      i.instanceId ==
                                      _selectedInstance!.instanceId,
                                ))
                            ? Container(
                                key: const ValueKey(
                                  'no_instance_selected_or_accepted',
                                ),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                child: Text(
                                  appLocalizations
                                      .jobAcceptSheetSelectDayPrompt,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 15,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : _InstanceDetails(
                                key: ValueKey(_selectedInstance!.instanceId),
                                instance: _selectedInstance!,
                                appLocalizations: appLocalizations,
                              ),
                      ),
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

  Widget _statTile({
    IconData? icon,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: 26, color: Colors.black87.withAlpha(178))
        else
          const SizedBox(height: 26, width: 26),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
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
    final payLabel = appLocalizations.jobAcceptSheetHeaderAvgPay;
    final estTimeLabel = appLocalizations.jobAcceptSheetHeaderAvgTime;
    final driveTimeLabel = appLocalizations.jobAcceptSheetHeaderDriveTime;
    final recommendedStartLabel =
        appLocalizations.jobAcceptSheetRecommendedStart;
    final serviceWindowLabel = appLocalizations.jobAcceptSheetServiceWindow;
    final buildingsLabel = appLocalizations.jobAcceptSheetBuildings;
    final floorsLabel = appLocalizations.jobAcceptSheetFloors;
    final unitsLabel = appLocalizations.jobAcceptSheetUnits;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // First Row of details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _detailItem(
                    icon: Icons.attach_money,
                    text: '${instance.pay.toStringAsFixed(0)} USD',
                    color: Colors.green,
                    label: payLabel,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _detailItem(
                    icon: Icons.timer_outlined,
                    text: instance.displayTime,
                    color: Colors.black87,
                    label: estTimeLabel,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _detailItem(
                    icon: Icons.directions_car_outlined,
                    text: instance.displayTravelTime,
                    color: Colors.black87,
                    label: driveTimeLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Second Row of details
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _TimeInfoTile(
                    icon: Icons.access_time_outlined,
                    label: recommendedStartLabel,
                    workerTime: instance.workerStartTimeHint,
                    propertyTime: instance.startTimeHint,
                    appLocalizations: appLocalizations,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TimeInfoTile(
                    icon: Icons.hourglass_empty_outlined,
                    label: serviceWindowLabel,
                    workerTime: instance.workerServiceWindowStart,
                    workerEndTime: instance.workerServiceWindowEnd,
                    propertyTime: instance.propertyServiceWindowStart,
                    propertyEndTime: instance.propertyServiceWindowEnd,
                    appLocalizations: appLocalizations,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _detailItem(
                    icon: Icons.apartment_outlined,
                    text:
                        '${instance.numberOfBuildings} bldg${instance.numberOfBuildings == 1 ? "" : "s"}',
                    color: Colors.black87,
                    label: buildingsLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _detailItem(
                    icon: Icons.stairs_outlined,
                    text: instance.floorsLabel,
                    color: Colors.black87,
                    label: floorsLabel,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _detailItem(
                    icon: Icons.home_outlined,
                    text: instance.totalUnitsLabel,
                    color: Colors.black87,
                    label: unitsLabel,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailItem({
    IconData? icon,
    required String text,
    required Color color,
    required String label,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        if (icon != null)
          Icon(icon, size: 24, color: color.withAlpha(225))
        else
          const SizedBox(height: 24, width: 24),
        const SizedBox(height: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// A specialized tile for displaying time ranges with timezone differences.
class _TimeInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String workerTime;
  final String? workerEndTime;
  final String propertyTime;
  final String? propertyEndTime;
  final AppLocalizations appLocalizations;

  const _TimeInfoTile({
    required this.icon,
    required this.label,
    required this.workerTime,
    required this.propertyTime,
    this.workerEndTime,
    this.propertyEndTime,
    required this.appLocalizations,
  });

  @override
  Widget build(BuildContext context) {
    final formattedWorkerStart = formatTime(context, workerTime);
    final formattedWorkerEnd = workerEndTime != null
        ? formatTime(context, workerEndTime!)
        : null;
    final workerDisplay = formattedWorkerEnd != null
        ? '$formattedWorkerStart - $formattedWorkerEnd'
        : formattedWorkerStart;

    final formattedPropertyStart = formatTime(context, propertyTime);
    final formattedPropertyEnd = propertyEndTime != null
        ? formatTime(context, propertyEndTime!)
        : null;
    final propertyDisplay = formattedPropertyEnd != null
        ? '$formattedPropertyStart - $formattedPropertyEnd'
        : formattedPropertyStart;

    final showPropertyTime =
        propertyTime.isNotEmpty && workerDisplay != propertyDisplay;

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Icon(icon, size: 24, color: Colors.black87.withAlpha(225)),
        const SizedBox(height: 8),
        Text(
          workerDisplay,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (showPropertyTime) ...[
          const SizedBox(height: 2),
          Text(
            appLocalizations.jobAcceptSheetPropertyTimeLocal(propertyDisplay),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

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
