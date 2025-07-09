// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/job_definition_admin.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/job_definition_form_notifier.dart';
import 'package:poof_admin/features/account/state/job_definition_form_state.dart';

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
  ConsumerState<JobDefinitionFormPage> createState() => _JobDefinitionFormPageState();
}

class _JobDefinitionFormPageState extends ConsumerState<JobDefinitionFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _frequencyController;

  @override
  void initState() {
    super.initState();
    final j = widget.jobDefinition;
    _titleController = TextEditingController(text: j?.title);
    _frequencyController = TextEditingController(text: j?.frequency);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _frequencyController.dispose();
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
      'frequency': _frequencyController.text.trim(),
    };

    final notifier = ref.read(jobDefinitionFormProvider.notifier);
    final success = widget.isEditMode
        ? false // TODO: await notifier.updateJobDefinition(widget.jobDefinition!.id, widget.pmId, data)
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(_titleController, 'Title', fieldErrors),
              _buildTextField(_frequencyController, 'Frequency (e.g., DAILY)', fieldErrors),
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
    final fieldKey = label.toLowerCase().split('(').first.trim().replaceAll(' ', '_');

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