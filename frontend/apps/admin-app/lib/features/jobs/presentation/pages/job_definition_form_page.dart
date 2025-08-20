import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:poof_admin/features/account/data/models/building_admin.dart';
import 'package:poof_admin/features/account/data/models/dumpster_admin.dart';
import 'package:poof_admin/features/jobs/data/models/job_definition_admin.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/jobs/providers/job_providers.dart';
import 'package:poof_admin/features/jobs/state/job_definition_form_notifier.dart';
import 'package:poof_admin/features/jobs/state/job_definition_form_state.dart';

class JobDefinitionFormPage extends ConsumerStatefulWidget {
  final String pmId;
  final String propertyId;
  final JobDefinitionAdmin? jobDefinition;

  const JobDefinitionFormPage({
    super.key,
    required this.pmId,
    required this.propertyId,
    this.jobDefinition,
  });

  bool get isEditMode => jobDefinition != null;

  @override
  ConsumerState<JobDefinitionFormPage> createState() =>
      _JobDefinitionFormPageState();
}

class _JobDefinitionFormPageState extends ConsumerState<JobDefinitionFormPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _intervalWeeksController;

  // State
  String? _frequency;
  Set<int> _selectedWeekdays = {};
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _earliestStartTime;
  TimeOfDay? _latestStartTime;
  TimeOfDay? _startTimeHint;
  bool _skipHolidays = false;
  bool _proofPhotosRequired = true;
  final List<String> _selectedBuildingIds = [];
  final List<String> _selectedDumpsterIds = [];
  final List<DailyPayEstimateAdmin> _dailyPayEstimates = [];

  @override
  void initState() {
    super.initState();
    final j = widget.jobDefinition;
    _titleController = TextEditingController(text: j?.title);
    _descriptionController = TextEditingController(text: j?.description);
    _intervalWeeksController =
        TextEditingController(text: j?.intervalWeeks?.toString() ?? '1');
    _frequency = j?.frequency ?? 'DAILY';
    _selectedWeekdays = j?.weekdays.toSet() ?? {};
    _startDate = j?.startDate;
    _endDate = j?.endDate;
    _earliestStartTime = j?.earliestStartTime;
    _latestStartTime = j?.latestStartTime;
    _startTimeHint = j?.startTimeHint;
    _skipHolidays = j?.skipHolidays ?? false;
    _proofPhotosRequired = j?.completionRules?.proofPhotosRequired ?? true;

    if (j != null) {
      _selectedBuildingIds.addAll(j.assignedBuildingIds);
      _selectedDumpsterIds.addAll(j.dumpsterIds);
      _dailyPayEstimates.addAll(j.dailyPayEstimates);
    } else {
      // Initialize with default pay estimates for a new job
      for (int i = 0; i < 7; i++) {
        _dailyPayEstimates.add(DailyPayEstimateAdmin(
            dayOfWeek: i, basePay: 20.0, estimatedTimeMinutes: 60));
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _intervalWeeksController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return 'Not Set';
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat.jm().format(dt);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not Set';
    return DateFormat.yMMMd().format(date);
  }

  DateTime _toUtcDateTime(DateTime date, TimeOfDay time) {
    final localDateTime =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    return localDateTime.toUtc();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please correct the errors in the form.')),
      );
      return;
    }
    if (_earliestStartTime == null || _latestStartTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start and End times are required.')),
      );
      return;
    }
    if (_startDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start Date is required.')),
      );
      return;
    }

    // Dummy date for time serialization
    final now = DateTime.now();

    final data = {
      'property_id': widget.propertyId,
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'assigned_building_ids': _selectedBuildingIds,
      'dumpster_ids': _selectedDumpsterIds,
      'frequency': _frequency,
      'weekdays': _frequency == 'CUSTOM' ? _selectedWeekdays.toList() : [],
      'interval_weeks': _frequency == 'CUSTOM'
          ? int.tryParse(_intervalWeeksController.text)
          : null,
      'start_date': _startDate!.toIso8601String(),
      'end_date': _endDate?.toIso8601String(),
      'earliest_start_time':
          _toUtcDateTime(now, _earliestStartTime!).toIso8601String(),
      'latest_start_time':
          _toUtcDateTime(now, _latestStartTime!).toIso8601String(),
      'start_time_hint': _startTimeHint != null
          ? _toUtcDateTime(now, _startTimeHint!).toIso8601String()
          : null,
      'skip_holidays': _skipHolidays,
      'completion_rules': {
        'proof_photos_required': _proofPhotosRequired,
      },
      'daily_pay_estimates':
          _dailyPayEstimates.map((e) => e.toJson()).toList(),
    };

    final notifier = ref.read(jobDefinitionFormProvider.notifier);
    final success = widget.isEditMode
        ? await notifier.updateJobDefinition(
            widget.jobDefinition!.id, widget.pmId, data)
        : await notifier.createJobDefinition(widget.pmId, data);

    if (success && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(jobDefinitionFormProvider);
    final snapshotAsync = ref.watch(pmSnapshotProvider(widget.pmId));

    ref.listen<JobDefinitionFormState>(jobDefinitionFormProvider, (_, state) {
      state.whenOrNull(
        error: (message, _) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        },
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode
            ? 'Edit Job Definition'
            : 'Create Job Definition'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              onPressed: formState.isLoading ? null : _submit,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error loading data: $err')),
        data: (snapshot) {
          final property = snapshot.properties
              .firstWhere((p) => p.id == widget.propertyId);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildSectionTitle('Basic Information'),
                _buildTextField(_titleController, 'Title'),
                _buildTextField(_descriptionController, 'Description',
                    isRequired: false),
                _buildMultiSelect(
                  context,
                  title: 'Buildings',
                  allItems: property.buildings,
                  selectedIds: _selectedBuildingIds,
                ),
                _buildMultiSelect(
                  context,
                  title: 'Dumpsters',
                  allItems: property.dumpsters,
                  selectedIds: _selectedDumpsterIds,
                ),
                const SizedBox(height: 16),
                _buildSectionTitle('Schedule'),
                _buildDropdown(
                    _frequency,
                    'Frequency',
                    ['DAILY', 'WEEKDAYS', 'WEEKLY', 'BIWEEKLY', 'CUSTOM'],
                    (val) => setState(() => _frequency = val)),
                if (_frequency == 'CUSTOM') ...[
                  const SizedBox(height: 8),
                  _buildWeekdaySelector(),
                  _buildTextField(
                      _intervalWeeksController, 'Interval (Weeks)',
                      isNumeric: true),
                ],
                _buildDatePicker(context, 'Start Date', _startDate,
                    (date) => setState(() => _startDate = date)),
                _buildDatePicker(context, 'End Date (Optional)', _endDate,
                    (date) => setState(() => _endDate = date)),
                _buildTimePicker(
                    context,
                    'Earliest Start Time',
                    _earliestStartTime,
                    (time) => setState(() => _earliestStartTime = time)),
                _buildTimePicker(context, 'Latest Start Time', _latestStartTime,
                    (time) => setState(() => _latestStartTime = time)),
                SwitchListTile(
                  title: const Text('Skip Holidays'),
                  value: _skipHolidays,
                  onChanged: (val) => setState(() => _skipHolidays = val),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                _buildSectionTitle('Pay & Rules'),
                SwitchListTile(
                  title: const Text('Proof Photos Required'),
                  value: _proofPhotosRequired,
                  onChanged: (val) =>
                      setState(() => _proofPhotosRequired = val),
                  contentPadding: EdgeInsets.zero,
                ),
                _buildDailyPayEstimates(),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: formState.isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 16)),
                    child: formState.isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white))
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool isRequired = true,
    bool isNumeric = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        inputFormatters:
            isNumeric ? [FilteringTextInputFormatter.digitsOnly] : [],
        validator: (value) {
          if (isRequired && (value == null || value.isEmpty)) {
            return '$label is required.';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildDropdown(String? currentValue, String label, List<String> items,
      ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: currentValue,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
        validator: (value) =>
            value == null ? 'Please select a value.' : null,
      ),
    );
  }

  Widget _buildWeekdaySelector() {
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Weekdays',
          border: OutlineInputBorder(),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: List<Widget>.generate(7, (int index) {
            return FilterChip(
              label: Text(days[index]),
              selected: _selectedWeekdays.contains(index),
              onSelected: (bool selected) {
                setState(() {
                  if (selected) {
                    _selectedWeekdays.add(index);
                  } else {
                    _selectedWeekdays.remove(index);
                  }
                });
              },
            );
          }),
        ),
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context, String label, DateTime? value,
      ValueChanged<DateTime> onDateSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
          );
          if (date != null) {
            onDateSelected(date);
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          child: Text(_formatDate(value)),
        ),
      ),
    );
  }

  Widget _buildTimePicker(BuildContext context, String label, TimeOfDay? value,
      ValueChanged<TimeOfDay> onTimeSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InkWell(
        onTap: () async {
          final time = await showTimePicker(
            context: context,
            initialTime: value ?? TimeOfDay.now(),
          );
          if (time != null) {
            onTimeSelected(time);
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          child: Text(_formatTime(value)),
        ),
      ),
    );
  }

  Widget _buildMultiSelect<T>(
    BuildContext context, {
    required String title,
    required List<T> allItems,
    required List<String> selectedIds,
  }) {
    String buttonText = '$title (${selectedIds.length} selected)';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.list),
        label: Text('Select $buttonText'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
          alignment: Alignment.centerLeft,
          foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
        ),
        onPressed: () => _showMultiSelectDialog(context,
            title: title, allItems: allItems, selectedIds: selectedIds),
      ),
    );
  }

  Future<void> _showMultiSelectDialog<T>(
    BuildContext context, {
    required String title,
    required List<T> allItems,
    required List<String> selectedIds,
  }) async {
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Select $title'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: allItems.length,
                itemBuilder: (context, index) {
                  final item = allItems[index];
                  late String itemId;
                  late String itemTitle;

                  if (item is BuildingAdmin) {
                    itemId = item.id;
                    itemTitle = item.buildingName;
                  } else if (item is DumpsterAdmin) {
                    itemId = item.id;
                    itemTitle = 'Dumpster #${item.dumpsterNumber}';
                  }

                  final isSelected = selectedIds.contains(itemId);

                  return CheckboxListTile(
                    title: Text(itemTitle),
                    value: isSelected,
                    onChanged: (bool? value) {
                      setDialogState(() {
                        if (value == true) {
                          selectedIds.add(itemId);
                        } else {
                          selectedIds.remove(itemId);
                        }
                      });
                      setState(() {});
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              )
            ],
          );
        });
      },
    );
  }

  Widget _buildDailyPayEstimates() {
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Daily Pay & Time Estimates',
          border: OutlineInputBorder(),
        ),
        child: Column(
          children: List.generate(_dailyPayEstimates.length, (index) {
            final estimate = _dailyPayEstimates[index];
            return Row(
              children: [
                SizedBox(
                    width: 40, child: Text(days[estimate.dayOfWeek])),
                const SizedBox(width: 8),
                Expanded(
                  child: _PayEstimateField(
                    label: 'Pay',
                    initialValue: estimate.basePay.toString(),
                    onChanged: (val) {
                      setState(() {
                        _dailyPayEstimates[index] = DailyPayEstimateAdmin(
                          dayOfWeek: estimate.dayOfWeek,
                          basePay: double.tryParse(val) ?? 0,
                          estimatedTimeMinutes:
                              estimate.estimatedTimeMinutes,
                        );
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PayEstimateField(
                    label: 'Mins',
                    isMinutes: true,
                    initialValue:
                        estimate.estimatedTimeMinutes.toString(),
                    onChanged: (val) {
                      setState(() {
                        _dailyPayEstimates[index] = DailyPayEstimateAdmin(
                          dayOfWeek: estimate.dayOfWeek,
                          basePay: estimate.basePay,
                          estimatedTimeMinutes: int.tryParse(val) ?? 0,
                        );
                      });
                    },
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _PayEstimateField extends StatelessWidget {
  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool isMinutes;

  const _PayEstimateField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.isMinutes = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixText: isMinutes ? null : '\$',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      keyboardType: TextInputType.numberWithOptions(decimal: !isMinutes),
      inputFormatters: [
        isMinutes
            ? FilteringTextInputFormatter.digitsOnly
            : FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
      ],
    );
  }
}