// frontend/apps/admin-app/lib/features/account/presentation/pages/job_definition_form_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/building_admin.dart';
import 'package:poof_admin/features/account/data/models/dumpster_admin.dart';
import 'package:poof_admin/features/jobs/data/models/job_definition_admin.dart';
import 'package:poof_admin/features/account/data/models/property_admin.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
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
  late final TextEditingController _titleController;
  late final TextEditingController _windowController;
  late final TextEditingController _payRateController;

  String? _scheduleType;
  final List<String> _selectedBuildingIds = [];
  final List<String> _selectedDumpsterIds = [];

  @override
  void initState() {
    super.initState();
    final j = widget.jobDefinition;
    _titleController = TextEditingController(text: j?.title);
    _scheduleType = j?.scheduleType;
    _windowController =
        TextEditingController(text: j?.jobWindowMinutes.toString());
    _payRateController = TextEditingController(text: j?.payRate.toString());
    if (j != null) {
      _selectedBuildingIds.addAll(j.buildingIds);
      _selectedDumpsterIds.addAll(j.dumpsterIds);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _windowController.dispose();
    _payRateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final data = {
      'manager_id': widget.pmId,
      'property_id': widget.propertyId,
      'title': _titleController.text.trim(),
      'schedule_type': _scheduleType,
      'job_window_minutes': int.parse(_windowController.text.trim()),
      'pay_rate': double.parse(_payRateController.text.trim()),
      'building_ids': _selectedBuildingIds,
      'dumpster_ids': _selectedDumpsterIds,
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
    final fieldErrors =
        formState.maybeWhen(error: (_, errors) => errors, orElse: () => null);
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
        title: Text(widget.isEditMode ? 'Edit Job' : 'Create Job'),
      ),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error loading data: $err')),
        data: (snapshot) {
          final property = snapshot.properties
              .firstWhere((p) => p.id == widget.propertyId);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildReadOnlyTextField('Manager ID', widget.pmId),
                  _buildReadOnlyTextField('Property ID', widget.propertyId),
                  _buildTextField(_titleController, 'Title', fieldErrors),
                  _buildDropdown(_scheduleType, 'Schedule Type',
                      ['DAILY', 'WEEKLY', 'MONTHLY']),
                  _buildTextField(
                      _payRateController, 'Pay Rate (\$)', fieldErrors,
                      isNumeric: true),
                  _buildTextField(
                      _windowController, 'Job Window (minutes)', fieldErrors,
                      isNumeric: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Job Window is required.';
                        }
                        final minutes = int.tryParse(value);
                        if (minutes == null) return 'Must be a valid number.';
                        if (minutes < 90) return 'Window must be at least 90 minutes.';
                        return null;
                      }),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: formState.maybeWhen(
                          loading: () => null, orElse: () => _submit),
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: formState.maybeWhen(
                        loading: () => const SizedBox(
                            height: 24,
                            width: 24,
                            child:
                                CircularProgressIndicator(color: Colors.white)),
                        orElse: () => const Text('Save'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReadOnlyTextField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          fillColor: Theme.of(context).disabledColor.withOpacity(0.05),
          filled: true,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    Map<String, String>? fieldErrors, {
    bool isRequired = true,
    bool isNumeric = false,
    String? Function(String?)? validator,
  }) {
    final fieldKey =
        label.toLowerCase().split('(').first.trim().replaceAll(' ', '_');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorText: fieldErrors?[fieldKey],
        ),
        keyboardType: isNumeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: isNumeric
            ? [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))]
            : [],
        validator: validator ??
            (value) {
              if (isRequired && (value == null || value.isEmpty)) {
                return '$label is required.';
              }
              return null;
            },
      ),
    );
  }

  Widget _buildDropdown(String? currentValue, String label, List<String> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<String>(
        value: currentValue,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: items
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: (value) {
          setState(() => _scheduleType = value);
        },
        validator: (value) =>
            value == null ? 'Please select a schedule type.' : null,
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
                      // This setState is for the main page form
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
}