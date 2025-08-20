// frontend/apps/admin-app/lib/features/account/presentation/pages/property_form_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/property_admin.dart';
import 'package:poof_admin/features/account/presentation/widgets/us_states_dropdown.dart';
import 'package:poof_admin/features/account/state/property_form_notifier.dart';
import 'package:poof_admin/features/account/state/property_form_state.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';

class PropertyFormPage extends ConsumerStatefulWidget {
  final String pmId;
  final PropertyAdmin? property;

  const PropertyFormPage({
    super.key,
    required this.pmId,
    this.property,
  });

  bool get isEditMode => property != null;

  @override
  ConsumerState<PropertyFormPage> createState() => _PropertyFormPageState();
}

class _PropertyFormPageState extends ConsumerState<PropertyFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _zipController;
  late final TextEditingController _timezoneController;
  late final TextEditingController _latController;
  late final TextEditingController _lonController;
  String? _selectedState;

  @override
  void initState() {
    super.initState();
    final p = widget.property;
    _nameController = TextEditingController(text: p?.propertyName);
    _addressController = TextEditingController(text: p?.address);
    _cityController = TextEditingController(text: p?.city);
    _selectedState = p?.state;
    _zipController = TextEditingController(text: p?.zipCode);
    _timezoneController = TextEditingController(text: p?.timeZone);
    _latController = TextEditingController(text: p?.latitude.toString());
    _lonController = TextEditingController(text: p?.longitude.toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _zipController.dispose();
    _timezoneController.dispose();
    _latController.dispose();
    _lonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final data = {
      'manager_id': widget.pmId,
      'property_name': _nameController.text.trim(),
      'address': _addressController.text.trim(),
      'city': _cityController.text.trim(),
      'state': _selectedState!,
      'zip_code': _zipController.text.trim(),
      'timezone': _timezoneController.text.trim(),
      'latitude': double.tryParse(_latController.text.trim()) ?? 0.0,
      'longitude': double.tryParse(_lonController.text.trim()) ?? 0.0,
    };

    final notifier = ref.read(propertyFormProvider.notifier);
    final success = widget.isEditMode
        ? await notifier.updateProperty(widget.property!.id, data)
        : await notifier.createProperty(data);

    if (success && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(propertyFormProvider);
    final fieldErrors =
        formState.maybeWhen(error: (_, errors) => errors, orElse: () => null);

    ref.listen<PropertyFormState>(propertyFormProvider, (_, state) {
      state.whenOrNull(
        error: (message, _) {
          // Show general error if no field errors are present
          if (fieldErrors == null || fieldErrors.isEmpty) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(message)));
          }
        },
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Property' : 'Create Property'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildReadOnlyTextField('Manager ID', widget.pmId),
              _buildTextField(_nameController, 'Property Name', fieldErrors),
              _buildTextField(_addressController, 'Address', fieldErrors),
              _buildTextField(_cityController, 'City', fieldErrors),
              Row(
                children: [
                  Expanded(
                    child: StateDropdown(
                      selectedValue: _selectedState,
                      errorText: fieldErrors?['state'],
                      onChanged: (newValue) {
                        setState(() {
                          _selectedState = newValue;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _buildTextField(_zipController, 'Zip Code', fieldErrors)),
                ],
              ),
              _buildTextField(_timezoneController, 'Timezone (e.g., America/New_York)', fieldErrors),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(_latController, 'Latitude', fieldErrors,
                        isNumeric: true),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(_lonController, 'Longitude', fieldErrors,
                        isNumeric: true),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      formState.maybeWhen(loading: () => null, orElse: () => _submit),
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
  }) {
    // Convert label to snake_case for map lookup
    final fieldKey = label.toLowerCase().replaceAll(' ', '_');

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
          if (isNumeric && value != null && double.tryParse(value) == null) {
            return 'Please enter a valid number.';
          }
          return null;
        },
      ),
    );
  }
}