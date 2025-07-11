import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/property_manager_admin.dart';
import 'package:poof_admin/features/account/presentation/widgets/us_states_dropdown.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/pm_form_notifier.dart';
import 'package:poof_admin/features/account/state/pm_form_state.dart';

class PmFormPage extends ConsumerStatefulWidget {
  final PropertyManagerAdmin? pm;
  const PmFormPage({super.key, this.pm});

  bool get isEditMode => pm != null;

  @override
  ConsumerState<PmFormPage> createState() => _PmFormPageState();
}

class _PmFormPageState extends ConsumerState<PmFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _businessNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _zipController;
  String? _selectedState;

  @override
  void initState() {
    super.initState();
    _businessNameController =
        TextEditingController(text: widget.pm?.businessName);
    _emailController = TextEditingController(text: widget.pm?.email);
    _phoneController = TextEditingController(text: widget.pm?.phone);
    _addressController =
        TextEditingController(text: widget.pm?.businessAddress);
    _cityController = TextEditingController(text: widget.pm?.city);
    _selectedState = widget.pm?.state;
    _zipController = TextEditingController(text: widget.pm?.zipCode);
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  void _resetFormFields(PropertyManagerAdmin pm) {
    setState(() {
      _businessNameController.text = pm.businessName;
      _emailController.text = pm.email;
      _phoneController.text = pm.phone ?? '';
      _addressController.text = pm.businessAddress;
      _cityController.text = pm.city;
      _selectedState = pm.state;
      _zipController.text = pm.zipCode;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final data = {
      'business_name': _businessNameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone': _phoneController.text.trim(),
      'business_address': _addressController.text.trim(),
      'city': _cityController.text.trim(),
      'state': _selectedState!,
      'zip_code': _zipController.text.trim(),
    };

    final notifier = ref.read(pmFormProvider.notifier);
    final success;
    if (widget.isEditMode) {
      final payload = {'id': widget.pm!.id, ...data};
      success = await notifier.updatePm(payload);
    } else {
      success = await notifier.createPm(data);
    }

    if (success && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(pmFormProvider);
    final fieldErrors =
        formState.maybeWhen(error: (_, errors) => errors, orElse: () => null);

    ref.listen<PmFormState>(pmFormProvider, (_, state) {
      state.whenOrNull(
        error: (message, errors) {
          // Only show SnackBar for general errors, not field-specific ones
          if (errors == null || errors.isEmpty) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(message)));
          }
        },
        conflict: (latestEntity, message) {
          showDialog(
            context: context,
            barrierDismissible: false, // User must choose an action
            builder: (BuildContext dialogContext) {
              return AlertDialog(
                title: const Text('Conflict Detected'),
                content: Text(
                    '$message\n\nYour unsaved changes are still in the form. You can overwrite the server version or reload to see the latest data.'),
                actions: <Widget>[
                  TextButton(
                    child: const Text('Reload'),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _resetFormFields(latestEntity);
                      // Reset state to initial so dialog doesn't pop up again
                      ref.read(pmFormProvider.notifier).state =
                          const PmFormState.initial();
                    },
                  ),
                  ElevatedButton(
                    child: const Text('Overwrite'),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _submit(); // Re-attempt submission
                    },
                  ),
                ],
              );
            },
          );
        },
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode
            ? 'Edit Property Manager'
            : 'Create Property Manager'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isEditMode && widget.pm != null)
                 _buildReadOnlyTextField('Property Manager ID', widget.pm!.id),
              _buildTextField(
                  _businessNameController, 'Business Name', fieldErrors),
              _buildTextField(_emailController, 'Email', fieldErrors,
                  isEmail: true),
              _buildTextField(
                  _phoneController, 'Phone Number (Optional)', fieldErrors,
                  isPhone: true, isRequired: false),
              _buildTextField(
                  _addressController, 'Business Address', fieldErrors),
              _buildTextField(_cityController, 'City', fieldErrors),
              StateDropdown(
                selectedValue: _selectedState,
                errorText: fieldErrors?['state'],
                onChanged: (newValue) {
                  setState(() {
                    _selectedState = newValue;
                  });
                },
              ),
              _buildTextField(_zipController, 'Zip Code', fieldErrors),
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
    bool isEmail = false,
    bool isPhone = false,
  }) {
    // Convert label to snake_case for map lookup
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
        keyboardType: isEmail
            ? TextInputType.emailAddress
            : (isPhone ? TextInputType.phone : TextInputType.text),
        validator: (value) {
          if (isRequired && (value == null || value.isEmpty)) {
            return '$label is required.';
          }
          if (isEmail &&
              value != null &&
              !RegExp(r'^.+@.+\..+$').hasMatch(value)) {
            return 'Please enter a valid email.';
          }
          return null;
        },
      ),
    );
  }
}