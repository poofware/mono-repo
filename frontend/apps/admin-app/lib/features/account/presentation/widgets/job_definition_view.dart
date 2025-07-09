// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/data/models/job_definition_admin.dart';
import 'package:poof_admin/features/account/presentation/widgets/confirmation_dialog.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';

class JobDefinitionView extends ConsumerWidget {
  final List<JobDefinitionAdmin> jobDefinitions;
  const JobDefinitionView({super.key, required this.jobDefinitions});

  Future<void> _deleteJobDefinition(BuildContext context, WidgetRef ref,
      String jobDefinitionId, String pmId) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Delete Job Definition?',
      content:
          'This will soft-delete this job definition. This action cannot be undone.',
    );
    if (confirmed) {
      await ref
          .read(pmsDetailProvider.notifier)
          .deleteJobDefinition(jobDefinitionId, pmId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (jobDefinitions.isEmpty) {
      return const Text('No job definitions for this property.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: jobDefinitions
          .map((job) => ListTile(
                dense: true,
                title: Text(job.title),
                subtitle: Text('Frequency: ${job.frequency}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit Job Definition',
                      onPressed: () => context.go(
                        '/dashboard/pms/${job.managerId}/properties/${job.propertyId}/job-definitions/edit',
                        extra: job,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Theme.of(context).colorScheme.error),
                      tooltip: 'Delete Job Definition',
                      onPressed: () =>
                          _deleteJobDefinition(context, ref, job.id, job.managerId),
                    ),
                  ],
                ),
              ))
          .toList(),
    );
  }
}