import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/pm_models.dart';
import 'package:poof_admin/features/account/presentation/widgets/detail_item.dart';
import 'package:poof_admin/features/account/presentation/widgets/property_card.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/account/state/pm_detail_state.dart';

class PmsDetailPage extends ConsumerWidget {
  final String pmId;
  const PmsDetailPage({super.key, required this.pmId});

  Future<void> _deletePm(
      BuildContext context, WidgetRef ref, PropertyManagerAdmin pm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final TextEditingController controller = TextEditingController();
        bool isMatch = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Delete Property Manager?'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    const Text(
                        'This will soft-delete the manager and all associated properties, buildings, etc. This action cannot be undone.'),
                    const SizedBox(height: 16),
                    Text.rich(
                      TextSpan(
                        text: 'To confirm, please type ',
                        children: <TextSpan>[
                          TextSpan(
                            text: pm.businessName,
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
                        labelText: 'Business Name',
                        hintText: pm.businessName,
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          isMatch = value.trim().toLowerCase() ==
                              pm.businessName.toLowerCase();
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
      final success =
          await ref.read(pmsDetailProvider.notifier).deletePm(pmId);
      if (success && context.mounted) {
        context.pop(); // Go back to the list view
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(pmSnapshotProvider(pmId));
    final textTheme = Theme.of(context).textTheme;

    ref.listen<PmDetailState>(pmsDetailProvider, (previous, next) {
      next.whenOrNull(
        loading: (message) =>
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))),
        success: (message) =>
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))),
        error: (error) => ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error))),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Property Manager Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete Property Manager',
            onPressed: () {
              snapshotAsync.whenData((snapshot) {
                _deletePm(context, ref, snapshot.propertyManager);
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Property Manager',
            onPressed: () {
              // The snapshot must be loaded to get the PM object to edit
              snapshotAsync.whenData(
                (snapshot) => context.go('/dashboard/pms/$pmId/edit',
                    extra: snapshot.propertyManager),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (snapshot) {
          return RefreshIndicator(
            onRefresh: () => ref.refresh(pmSnapshotProvider(pmId).future),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPmHeader(context, snapshot),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Properties', style: textTheme.headlineSmall),
                      IconButton(
                        icon: const Icon(Icons.add_business_outlined),
                        tooltip: 'Add Property',
                        onPressed: () => context.go('/dashboard/pms/$pmId/properties/new'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (snapshot.properties.isEmpty)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text('This manager has no properties.'),
                    ))
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: snapshot.properties.length,
                      itemBuilder: (context, index) {
                        return PropertyCard(property: snapshot.properties[index]);
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPmHeader(BuildContext context, PmsSnapshot snapshot) {
    final textTheme = Theme.of(context).textTheme;
    final pm = snapshot.propertyManager;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(pm.businessName, style: textTheme.headlineMedium),
        const SizedBox(height: 16),
        DetailItem(label: 'Email', value: pm.email),
        if (pm.phone != null) DetailItem(label: 'Phone', value: pm.phone!),
        DetailItem(
            label: 'Address',
            value:
                '${pm.businessAddress}, ${pm.city}, ${pm.state} ${pm.zipCode}'),
        DetailItem(
            label: 'Joined On',
            value: pm.createdAt.toLocal().toString().split(' ')[0]),
      ],
    );
  }
}