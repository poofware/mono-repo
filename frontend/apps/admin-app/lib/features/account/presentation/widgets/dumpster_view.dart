// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/dumpster_admin.dart';
import 'package:poof_admin/features/account/presentation/widgets/confirmation_dialog.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';

class DumpsterView extends ConsumerWidget {
  final List<DumpsterAdmin> dumpsters;
  final String pmId;
  final String propertyId;

  const DumpsterView({
    super.key,
    required this.dumpsters,
    required this.pmId,
    required this.propertyId,
  });

  Future<void> _deleteDumpster(
      BuildContext context, WidgetRef ref, String dumpsterId, String pmId) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Delete Dumpster?',
      content:
          'This will soft-delete this dumpster. This action cannot be undone.',
    );
    if (confirmed) {
      await ref.read(pmsDetailProvider.notifier).deleteDumpster(dumpsterId, pmId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (dumpsters.isEmpty) {
      return const Text('No dumpsters for this property.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: dumpsters
          .map((d) => ListTile(
                dense: true,
                title: Text('Dumpster #${d.dumpsterNumber}'),
                subtitle: Text('Coords: ${d.latitude}, ${d.longitude}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit Dumpster',
                      onPressed: () => context.go(
                        '/dashboard/pms/$pmId/properties/$propertyId/dumpsters/edit',
                        extra: d,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error),
                      tooltip: 'Delete Dumpster',
                      onPressed: () => _deleteDumpster(context, ref, d.id, pmId),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}