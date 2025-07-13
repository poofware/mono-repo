import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/property_admin.dart';
import 'package:poof_admin/features/account/presentation/widgets/building_view.dart';
import 'package:poof_admin/features/account/presentation/widgets/detail_item.dart';
import 'package:poof_admin/features/account/presentation/widgets/detail_section.dart';
import 'package:poof_admin/features/account/presentation/widgets/dumpster_view.dart';
import 'package:poof_admin/features/jobs/presentation/widgets/job_definition_view.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';

class PropertyCard extends ConsumerWidget {
  final PropertyAdmin property;
  const PropertyCard({super.key, required this.property});

  Future<void> _deleteProperty(
      BuildContext context, WidgetRef ref, PropertyAdmin property) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final TextEditingController controller = TextEditingController();
        bool isMatch = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Delete Property?'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    const Text(
                        'This will soft-delete this property and all its associated data. This action cannot be undone.'),
                    const SizedBox(height: 16),
                    Text.rich(
                      TextSpan(
                        text: 'To confirm, please type ',
                        children: <TextSpan>[
                          TextSpan(
                            text: property.propertyName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(text: ' into the box below.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: 'Property Name',
                        hintText: property.propertyName,
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          isMatch = value.trim().toLowerCase() ==
                              property.propertyName.toLowerCase();
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                TextButton(
                  onPressed: isMatch
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true && context.mounted) {
      await ref
          .read(pmsDetailProvider.notifier)
          .deleteProperty(property.id, property.managerId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(property.propertyName, style: Theme.of(context).textTheme.titleLarge),
        subtitle: Text(property.address),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Property',
              onPressed: () => context.go(
                '/dashboard/pms/${property.managerId}/properties/edit',
                extra: property,
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              tooltip: 'Delete Property',
              onPressed: () => _deleteProperty(context, ref, property),
            ),
            const Icon(Icons.expand_more), // Default ExpansionTile icon
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailItem(label: 'Timezone', value: property.timeZone),
                DetailItem(
                    label: 'Coordinates',
                    value: '${property.latitude}, ${property.longitude}'),
                const Divider(height: 32),
                DetailSection(
                  title: 'Buildings',
                  onAdd: () => context.go(
                    '/dashboard/pms/${property.managerId}/properties/${property.id}/buildings/new',
                  ),
                  child: BuildingView(property: property),
                ),
                const SizedBox(height: 16),
                DetailSection(
                  title: 'Dumpsters',
                  onAdd: () => context.go(
                    '/dashboard/pms/${property.managerId}/properties/${property.id}/dumpsters/new',
                  ),
                  child: DumpsterView(
                    dumpsters: property.dumpsters,
                    pmId: property.managerId,
                    propertyId: property.id,
                  ),
                ),
                const SizedBox(height: 16),
                DetailSection(
                  title: 'Job Definitions',
                  onAdd: () => context.go(
                    '/dashboard/pms/${property.managerId}/properties/${property.id}/job-definitions/new',
                  ),
                  child: JobDefinitionView(jobDefinitions: property.jobDefinitions),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}