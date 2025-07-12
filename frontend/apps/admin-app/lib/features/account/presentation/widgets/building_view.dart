// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/property_admin.dart';
import 'package:poof_admin/features/account/presentation/widgets/confirmation_dialog.dart';
import 'package:poof_admin/features/account/presentation/widgets/unit_list_view.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';

class BuildingView extends ConsumerWidget {
  final PropertyAdmin property;
  const BuildingView({super.key, required this.property});

  Future<void> _deleteBuilding(
      BuildContext context, WidgetRef ref, String buildingId, String pmId) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Delete Building?',
      content:
          'This will soft-delete this building and all its units. This action cannot be undone.',
    );
    if (confirmed) {
      await ref.read(pmsDetailProvider.notifier).deleteBuilding(buildingId, pmId);
    }
  }

  void _showAddUnitChoiceDialog(BuildContext context, WidgetRef ref, String pmId, String propertyId, String buildingId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add New Unit(s)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_box_outlined),
                title: const Text('Add a Single Unit'),
                onTap: () {
                  Navigator.of(context).pop();
                  context.go(
                    '/dashboard/pms/$pmId/properties/$propertyId/buildings/$buildingId/units/new',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_to_photos_outlined),
                title: const Text('Add Multiple Units (Bulk)'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showBulkCreateDialog(context, ref, pmId, propertyId, buildingId);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBulkCreateDialog(
    BuildContext context,
    WidgetRef ref,
    String pmId,
    String propertyId,
    String buildingId,
  ) async {
    final formKey = GlobalKey<FormState>();
    final prefixController = TextEditingController();
    final startController = TextEditingController();
    final endController = TextEditingController();

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must take action
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Bulk Create Units'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextFormField(
                    controller: prefixController,
                    decoration: const InputDecoration(
                      labelText: 'Unit Prefix (e.g., A-)',
                      hintText: 'Optional',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: startController,
                    decoration: const InputDecoration(
                      labelText: 'Start Number',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      if (int.tryParse(value) == null) {
                        return 'Invalid number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: endController,
                    decoration: const InputDecoration(
                      labelText: 'End Number',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      final end = int.tryParse(value);
                      final start = int.tryParse(startController.text);
                      if (end == null) return 'Invalid number';
                      if (start != null && end < start) {
                        return 'Must be >= start';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Create'),
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final success = await ref
                      .read(pmsDetailProvider.notifier)
                      .createBulkUnits(
                        pmId: pmId,
                        propertyId: propertyId,
                        buildingId: buildingId,
                        prefix: prefixController.text.trim(),
                        start: int.parse(startController.text),
                        end: int.parse(endController.text),
                      );
                  if (success && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                }
              },
            ),
          ],
        );
      },
    ).whenComplete(() {
      prefixController.dispose();
      startController.dispose();
      endController.dispose();
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (property.buildings.isEmpty) {
      return const Text('No buildings for this property.');
    }
    return Column(
      children: property.buildings.map((building) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ExpansionTile(
            title: Text(building.buildingName),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit Building',
                  onPressed: () => context.go(
                    '/dashboard/pms/${property.managerId}/properties/${property.id}/buildings/edit',
                    extra: building,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error),
                  tooltip: 'Delete Building',
                  onPressed: () => _deleteBuilding(
                      context, ref, building.id, property.managerId),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Add Unit'),
                          onPressed: () => _showAddUnitChoiceDialog(
                            context,
                            ref,
                            property.managerId,
                            property.id,
                            building.id,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    UnitListView(
                      units: building.units,
                      pmId: property.managerId,
                      propertyId: property.id,
                      buildingId: building.id,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}