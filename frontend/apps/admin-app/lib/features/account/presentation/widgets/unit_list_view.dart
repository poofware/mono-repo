// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/unit_admin.dart';
import 'package:poof_admin/features/account/presentation/widgets/confirmation_dialog.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';

class UnitListView extends ConsumerWidget {
  final List<UnitAdmin> units;
  final String pmId;
  final String propertyId;
  final String buildingId;

  const UnitListView({
    super.key,
    required this.units,
    required this.pmId,
    required this.propertyId,
    required this.buildingId,
  });

  Future<void> _deleteUnit(
      BuildContext context, WidgetRef ref, String unitId, String pmId) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Delete Unit?',
      content: 'This will soft-delete this unit. This action cannot be undone.',
    );
    if (confirmed) {
      await ref.read(pmsDetailProvider.notifier).deleteUnit(unitId, pmId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (units.isEmpty) {
      return const Text('No units in this building.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: units
          .map((unit) => ListTile(
                dense: true,
                title: Text('Unit: ${unit.unitNumber}'),
                subtitle: Text('Token: ${unit.tenantToken}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit Unit',
                      onPressed: () => context.go(
                        '/dashboard/pms/$pmId/properties/$propertyId/buildings/$buildingId/units/edit',
                        extra: unit,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error),
                      tooltip: 'Delete Unit',
                      onPressed: () => _deleteUnit(context, ref, unit.id, pmId),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}