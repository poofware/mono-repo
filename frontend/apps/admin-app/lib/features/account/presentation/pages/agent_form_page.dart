import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/agent_admin.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/agent_form_state.dart';

class AgentFormPage extends ConsumerStatefulWidget {
  final AgentAdmin? agent;

  const AgentFormPage({super.key, this.agent});

  bool get isEditMode => agent != null;

  @override
  ConsumerState<AgentFormPage> createState() => _AgentFormPageState();
}

class _AgentFormPageState extends ConsumerState<AgentFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _zipController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;

  @override
  void initState() {
    super.initState();
    final a = widget.agent;
    _nameController = TextEditingController(text: a?.name);
    _emailController = TextEditingController(text: a?.email);
    _phoneController = TextEditingController(text: a?.phoneNumber);
    _addressController = TextEditingController(text: a?.address);
    _cityController = TextEditingController(text: a?.city);
    _stateController = TextEditingController(text: a?.state);
    _zipController = TextEditingController(text: a?.zipCode);
    _latController =
        TextEditingController(text: a != null ? a.latitude.toString() : '');
    _lngController =
        TextEditingController(text: a != null ? a.longitude.toString() : '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final payload = {
      if (widget.agent != null) 'id': widget.agent!.id,
      'name': _nameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone_number': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
      'city': _cityController.text.trim(),
      'state': _stateController.text.trim(),
      'zip_code': _zipController.text.trim(),
      'latitude': double.tryParse(_latController.text.trim()) ?? 0.0,
      'longitude': double.tryParse(_lngController.text.trim()) ?? 0.0,
    };

    final notifier = ref.read(agentFormProvider.notifier);
    final success = widget.isEditMode
        ? await notifier.updateAgent(payload)
        : await notifier.createAgent(payload);

    if (success && mounted) {
      context.pop();
    }
  }

  Future<void> _delete() async {
    if (widget.agent == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Agent?'),
        content: const Text(
            'This will soft-delete this agent. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => context.pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      final success = await ref.read(agentFormProvider.notifier).deleteAgent(widget.agent!.id);
      if (success && mounted) {
        context.pop();
      }
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentFormProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Agent' : 'New Agent'),
        actions: [
          if (widget.isEditMode)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              tooltip: 'Delete Agent',
              onPressed: _delete,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (state is AgentFormError)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(state.message, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name'), validator: _required),
                    TextFormField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email'), validator: _required),
                    TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone Number'), validator: _required),
                    TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: 'Address'), validator: _required),
                    TextFormField(controller: _cityController, decoration: const InputDecoration(labelText: 'City'), validator: _required),
                    TextFormField(controller: _stateController, decoration: const InputDecoration(labelText: 'State (2 letters)'), validator: _required),
                    TextFormField(controller: _zipController, decoration: const InputDecoration(labelText: 'Zip Code'), validator: _required),
                    TextFormField(controller: _latController, decoration: const InputDecoration(labelText: 'Latitude'), keyboardType: TextInputType.number),
                    TextFormField(controller: _lngController, decoration: const InputDecoration(labelText: 'Longitude'), keyboardType: TextInputType.number),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: state is AgentFormLoading ? null : _submit,
                  child: Text(state is AgentFormLoading ? 'Saving...' : 'Save'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
