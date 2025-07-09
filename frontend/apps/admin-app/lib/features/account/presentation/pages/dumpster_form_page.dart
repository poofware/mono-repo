// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/dumpster_admin.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/dumpster_form_notifier.dart';
import 'package:poof_admin/features/account/state/dumpster_form_state.dart';

class DumpsterFormPage extends ConsumerStatefulWidget {
  final String pmId;
  final String propertyId;
  final DumpsterAdmin? dumpster;

  const DumpsterFormPage({
    super.key,
    required this.pmId,
    required this.propertyId,
    this.dumpster,
  });

  bool get isEditMode => dumpster != null;

  @override
  ConsumerState<DumpsterFormPage> createState() => _DumpsterFormPageState();
}

class _DumpsterFormPageState extends ConsumerState<DumpsterFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numberController;
  late final TextEditingController _latController;
  late final TextEditingController _lonController;

  @override
  void initState() {
    super.initState();
    final d = widget.dumpster;
    _numberController = TextEditingController(text: d?.dumpsterNumber);
    _latController = TextEditingController(text: d?.latitude.toString());
    _lonController = TextEditingController(text: d?.longitude.toString());
  }

  @override
  void dispose() {
    _numberController.dispose();
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
      'dumpster_number': _numberController.text.trim(),
      'latitude': double.parse(_latController.text.trim()),
      'longitude': double.parse(_lonController.text.trim()),
    };

    final notifier = ref.read(dumpsterFormProvider.notifier);
    final success = widget.isEditMode
        ? false // TODO: await notifier.updateDumpster(widget.dumpster!.id, widget.pmId, data)
        : await notifier.createDumpster(widget.pmId, data);

    if (success && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(dumpsterFormProvider);
    final fieldErrors =
        formState.maybeWhen(error: (_, errors) => errors, orElse: () => null);

    ref.listen<DumpsterFormState>(dumpsterFormProvider, (_, state) {
      state.whenOrNull(
        error: (message, _) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        },
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Dumpster' : 'Create Dumpster'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(_numberController, 'Dumpster Number', fieldErrors),
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