// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/unit_admin.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/unit_form_notifier.dart';
import 'package:poof_admin/features/account/state/unit_form_state.dart';

class UnitFormPage extends ConsumerStatefulWidget {
  final String pmId;
  final String propertyId;
  final String buildingId;
  final UnitAdmin? unit;

  const UnitFormPage({
    super.key,
    required this.pmId,
    required this.propertyId,
    required this.buildingId,
    this.unit,
  });

  bool get isEditMode => unit != null;

  @override
  ConsumerState<UnitFormPage> createState() => _UnitFormPageState();
}

class _UnitFormPageState extends ConsumerState<UnitFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _unitNumberController;

  @override
  void initState() {
    super.initState();
    final u = widget.unit;
    _unitNumberController = TextEditingController(text: u?.unitNumber);
  }

  @override
  void dispose() {
    _unitNumberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final data = {
      'property_id': widget.propertyId,
      'building_id': widget.buildingId,
      'unit_number': _unitNumberController.text.trim(),
    };

    final notifier = ref.read(unitFormProvider.notifier);
    final success = widget.isEditMode
        ? await notifier.updateUnit(widget.unit!.id, widget.pmId, data)
        : await notifier.createUnit(widget.pmId, data);

    if (success && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(unitFormProvider);
    final fieldErrors =
        formState.maybeWhen(error: (_, errors) => errors, orElse: () => null);

    ref.listen<UnitFormState>(unitFormProvider, (_, state) {
      state.whenOrNull(
        error: (message, _) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        },
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Unit' : 'Create Unit'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(_unitNumberController, 'Unit Number', fieldErrors),
              const SizedBox(height: 8),
              if (!widget.isEditMode)
                Text(
                  'A unique tenant token will be generated automatically upon creation.',
                  style: Theme.of(context).textTheme.bodySmall,
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
  }) {
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
        validator: (value) {
          if (isRequired && (value == null || value.isEmpty)) {
            return '$label is required.';
          }
          return null;
        },
      ),
    );
  }
}