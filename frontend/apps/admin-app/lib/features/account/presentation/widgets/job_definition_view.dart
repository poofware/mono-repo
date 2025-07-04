// NEW FILE
import 'package:flutter/material.dart';
import 'package:poof_admin/features/account/data/models/job_definition_admin.dart';

class JobDefinitionView extends StatelessWidget {
  final List<JobDefinitionAdmin> jobDefinitions;
  const JobDefinitionView({super.key, required this.jobDefinitions});

  @override
  Widget build(BuildContext context) {
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
              ))
          .toList(),
    );
  }
}