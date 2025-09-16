// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:poof_admin/features/account/data/models/unit_admin.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
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
  late final TextEditingController _tenantTokenController;
  String? _selectedFloorId;
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    final u = widget.unit;
    _unitNumberController = TextEditingController(text: u?.unitNumber);
    _tenantTokenController = TextEditingController(text: u?.tenantToken);
    _selectedFloorId = u?.floorId;
    if (!widget.isEditMode) {
      _tenantTokenController.text = _uuid.v4();
    }
  }

  @override
  void dispose() {
    _unitNumberController.dispose();
    _tenantTokenController.dispose();
    // no controllers to dispose for floorId dropdown
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final data = {
      'property_id': widget.propertyId,
      'building_id': widget.buildingId,
      'floor_id': _selectedFloorId,
      'unit_number': _unitNumberController.text.trim(),
      'tenant_token': _tenantTokenController.text.trim(),
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
              _buildFloorDropdown(fieldErrors),
               _buildTenantTokenField(fieldErrors),
              const SizedBox(height: 24),
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
Widget _buildTenantTokenField(Map<String, String>? fieldErrors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: _tenantTokenController,
        decoration: InputDecoration(
          labelText: 'Tenant Token',
          border: const OutlineInputBorder(),
          errorText: fieldErrors?['tenant_token'],
          suffixIcon: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Generate New Token',
            onPressed: () {
              setState(() {
                _tenantTokenController.text = _uuid.v4();
              });
            },
          ),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Tenant Token is required.';
          }
          return null;
        },
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

  Widget _buildFloorDropdown(Map<String, String>? fieldErrors) {
    // Pull floors from current property/building in memory via provider snapshot
    final snapshot = ref.read(pmSnapshotProvider(widget.pmId)).maybeWhen(
          data: (s) => s,
          orElse: () => null,
        );
    final floors = snapshot?.properties
            .firstWhere((p) => p.id == widget.propertyId)
            .buildings
            .firstWhere((b) => b.id == widget.buildingId)
            .floors ??
        [];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Floor',
          border: const OutlineInputBorder(),
          errorText: fieldErrors?['floor_id'],
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: _selectedFloorId,
            items: floors.map((f) => DropdownMenuItem<String>(
                  value: f.id,
                  child: Text('Floor ${f.number}'),
                )).toList(),
            onChanged: (val) {
              setState(() {
                _selectedFloorId = val;
              });
            },
          ),
        ),
      ),
    );
  }
}