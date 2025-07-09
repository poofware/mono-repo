// NEW FILE
import 'package:flutter/material.dart';
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
                          onPressed: () => context.go(
                            '/dashboard/pms/${property.managerId}/properties/${property.id}/buildings/${building.id}/units/new',
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