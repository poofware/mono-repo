// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/building_admin.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/building_form_notifier.dart';
import 'package:poof_admin/features/account/state/building_form_state.dart';

class BuildingFormPage extends ConsumerStatefulWidget {
  final String pmId;
  final String propertyId;
  final BuildingAdmin? building;

  const BuildingFormPage({
    super.key,
    required this.pmId,
    required this.propertyId,
    this.building,
  });

  bool get isEditMode => building != null;

  @override
  ConsumerState<BuildingFormPage> createState() => _BuildingFormPageState();
}

class _BuildingFormPageState extends ConsumerState<BuildingFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _latController;
  late final TextEditingController _lonController;

  @override
  void initState() {
    super.initState();
    final b = widget.building;
    _nameController = TextEditingController(text: b?.buildingName);
    _addressController = TextEditingController(text: b?.address);
    _latController = TextEditingController(text: b?.latitude?.toString());
    _lonController = TextEditingController(text: b?.longitude?.toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final data = {
      'property_id': widget.propertyId,
      'building_name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'latitude': double.tryParse(_latController.text.trim()),
      'longitude': double.tryParse(_lonController.text.trim()),
    };

    final notifier = ref.read(buildingFormProvider.notifier);
    final success = widget.isEditMode
        ? false // TODO: await notifier.updateBuilding(widget.building!.id, widget.pmId, data)
        : await notifier.createBuilding(widget.pmId, data);

    if (success && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(buildingFormProvider);
    final fieldErrors =
        formState.maybeWhen(error: (_, errors) => errors, orElse: () => null);

    ref.listen<BuildingFormState>(buildingFormProvider, (_, state) {
      state.whenOrNull(
        error: (message, _) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        },
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Building' : 'Create Building'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(_nameController, 'Building Name', fieldErrors),
              _buildTextField(_addressController, 'Address (Optional)', fieldErrors, isRequired: false),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(_latController, 'Latitude (Optional)', fieldErrors,
                        isNumeric: true, isRequired: false),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(_lonController, 'Longitude (Optional)', fieldErrors,
                        isNumeric: true, isRequired: false),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: formState.maybeWhen(loading: () => null, orElse: () => _submit),
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: formState.maybeWhen(
                    loading: () => const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white)),
                    orElse: () => const Text('Save'),
                  ),
                ),
              ),
            ],
          ),
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
  }) {
    // Convert label to snake_case for map lookup
    final fieldKey = label.toLowerCase().replaceAll(' (optional)', '').replaceAll(' ', '_');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorText: fieldErrors?[fieldKey],
        ),
        keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
        validator: (value) {
          if (isRequired && (value == null || value.isEmpty)) {
            return '$label is required.';
          }
          if (isNumeric && (value != null && value.isNotEmpty) && double.tryParse(value) == null) {
            return 'Please enter a valid number.';
          }
          return null;
        },
      ),
    );
  }
}