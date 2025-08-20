// lib/features/jobs/presentation/widgets/job_history_filters_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_constants.dart';
import '../../data/models/job_status.dart';
import '../../providers/job_providers.dart';
import '../../state/job_history_state.dart';

class JobHistoryFiltersWidget extends ConsumerStatefulWidget {
  const JobHistoryFiltersWidget({super.key});

  @override
  ConsumerState<JobHistoryFiltersWidget> createState() =>
      _JobHistoryFiltersWidgetState();
}

class _JobHistoryFiltersWidgetState
    extends ConsumerState<JobHistoryFiltersWidget> {
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentFilters = ref.read(jobFiltersProvider);
    if (currentFilters.dateRangePreset == DateRangePreset.custom) {
      _customStartDate = currentFilters.customStartDate;
      _customEndDate = currentFilters.customEndDate;
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final currentFilters = ref.read(jobFiltersProvider);
    DateTime initialPickerDate = DateTime.now();

    if (isStartDate) {
      initialPickerDate = _customStartDate ?? currentFilters.customStartDate ?? DateTime.now();
    } else {
      initialPickerDate = _customEndDate ?? currentFilters.customEndDate ?? DateTime.now();
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialPickerDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.primary,
                  onPrimary: Colors.white,
                  surface: Theme.of(context).cardColor,
                  onSurface: Theme.of(context).textTheme.bodyLarge?.color,
                ),
            dialogBackgroundColor: Theme.of(context).cardColor,
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _customStartDate = picked;
        } else {
          _customEndDate = picked;
        }
      });
    }
  }

  void _applyFilters() {
    final notifier = ref.read(jobFiltersProvider.notifier);
    final currentFilters = ref.watch(jobFiltersProvider);

    if (currentFilters.dateRangePreset == DateRangePreset.custom) {
      if (_customStartDate != null && _customEndDate != null && _customStartDate!.isAfter(_customEndDate!)) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Start date cannot be after end date.'), backgroundColor: Colors.redAccent),
        );
        return;
      }
      notifier.setCustomDateRange(_customStartDate, _customEndDate);
    }
    // For non-custom presets, the filter is already applied on change.
    // If you wanted an explicit apply button for all, you would call the notifier here too.
  }

  @override
  Widget build(BuildContext context) {
    final currentFilters = ref.watch(jobFiltersProvider);
    final notifier = ref.read(jobFiltersProvider.notifier);
    final DateFormat displayDateFormat = DateFormat('MMM d, yyyy');
    final currentYear = DateTime.now().year;

    // Define a breakpoint for switching between wide and narrow layouts
    const double kFiltersBreakpoint = 650.0;

    final inputDecoration = InputDecoration(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.kDefaultHorizontalSpacing,
        vertical: AppConstants.kDefaultVerticalSpacing * 0.75,
      ),
      color: Theme.of(context).cardColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > kFiltersBreakpoint;
          
          // Define widgets once to avoid code duplication
          final dateRangeFilter = DropdownButtonFormField<DateRangePreset>(
            value: currentFilters.dateRangePreset,
            isExpanded: true,
            decoration: inputDecoration,
            items: DateRangePreset.values.map((DateRangePreset value) {
              String text;
              switch (value) {
                case DateRangePreset.last7days: text = 'Last 7 Days'; break;
                case DateRangePreset.last30days: text = 'Last 30 Days'; break;
                case DateRangePreset.last90days: text = 'Last 90 Days'; break;
                case DateRangePreset.thisYear: text = 'This Year ($currentYear)'; break;
                case DateRangePreset.lastYear: text = 'Last Year (${currentYear - 1})'; break;
                case DateRangePreset.custom: text = 'Custom Range...'; break;
              }
              return DropdownMenuItem<DateRangePreset>(
                value: value,
                child: Text(text, style: const TextStyle(fontSize: 14)),
              );
            }).toList(),
            onChanged: (DateRangePreset? newValue) {
              if (newValue != null) {
                notifier.setDateRangePreset(newValue);
                if (newValue != DateRangePreset.custom) {
                  setState(() {
                    _customStartDate = null;
                    _customEndDate = null;
                  });
                } else {
                  final providerCustomStart = ref.read(jobFiltersProvider).customStartDate;
                  final providerCustomEnd = ref.read(jobFiltersProvider).customEndDate;
                  setState(() {
                    _customStartDate = providerCustomStart;
                    _customEndDate = providerCustomEnd;
                  });
                }
              }
            },
          );

          final statusFilter = DropdownButtonFormField<JobStatus?>(
            value: currentFilters.jobStatus,
            isExpanded: true,
            decoration: inputDecoration,
            hint: const Text('All Statuses', style: TextStyle(fontSize: 14, color: Colors.grey)),
            items: [
              const DropdownMenuItem<JobStatus?>(
                value: null,
                child: Text('All Statuses', style: TextStyle(fontSize: 14)),
              ),
              ...JobStatus.values
                  .where((s) => s != JobStatus.unknown)
                  .map((JobStatus value) {
                return DropdownMenuItem<JobStatus?>(
                  value: value,
                  child: Text(jobStatusToString(value), style: const TextStyle(fontSize: 14)),
                );
              }).toList(),
            ],
            onChanged: (JobStatus? newValue) {
              notifier.setJobStatusFilter(newValue);
            },
          );

          final applyButton = SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _applyFilters,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 2,
              ),
              child: const Icon(Icons.filter_alt_outlined, size: 22),
            ),
          );

          final customDatePickers = currentFilters.dateRangePreset == DateRangePreset.custom
              ? Padding(
                  padding: EdgeInsets.only(top: isWide ? 0 : AppConstants.kDefaultVerticalSpacing * 0.75),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Start Date:', style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => _selectDate(context, true),
                              child: InputDecorator(
                                decoration: inputDecoration.copyWith(hintText: 'Select start date'),
                                child: Text(
                                  _customStartDate != null ? displayDateFormat.format(_customStartDate!) : 'Not set',
                                  style: TextStyle(fontSize: 14, color: _customStartDate != null ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey[600]),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppConstants.kDefaultHorizontalSpacing / 2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('End Date:', style: Theme.of(context).textTheme.labelMedium),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () => _selectDate(context, false),
                              child: InputDecorator(
                                decoration: inputDecoration.copyWith(hintText: 'Select end date'),
                                child: Text(
                                  _customEndDate != null ? displayDateFormat.format(_customEndDate!) : 'Not set',
                                  style: TextStyle(fontSize: 14, color: _customEndDate != null ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey[600]),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink();

          if (isWide) {
            // WIDE (Desktop) LAYOUT
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Date Range:', style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 6),
                          dateRangeFilter,
                        ],
                      ),
                    ),
                    const SizedBox(width: AppConstants.kDefaultHorizontalSpacing / 2),
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status:', style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 6),
                          statusFilter,
                        ],
                      ),
                    ),
                    const SizedBox(width: AppConstants.kDefaultHorizontalSpacing / 2),
                    applyButton,
                  ],
                ),
                if (currentFilters.dateRangePreset == DateRangePreset.custom)
                  Padding(
                    padding: const EdgeInsets.only(top: AppConstants.kDefaultVerticalSpacing * 0.75),
                    child: customDatePickers
                  ),
              ],
            );
          } else {
            // NARROW (Mobile) LAYOUT
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Date Range:', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                dateRangeFilter,
                const SizedBox(height: AppConstants.kDefaultVerticalSpacing),
                Text('Status:', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                statusFilter,
                if (currentFilters.dateRangePreset == DateRangePreset.custom)
                  customDatePickers,
                const SizedBox(height: AppConstants.kDefaultVerticalSpacing * 1.5),
                SizedBox(width: double.infinity, child: applyButton),
              ],
            );
          }
        },
      ),
    );
  }
}