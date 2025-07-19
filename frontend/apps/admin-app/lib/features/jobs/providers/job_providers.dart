// frontend/apps/admin-app/lib/features/jobs/providers/job_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/jobs/data/repositories/admin_jobs_repository.dart';
import 'package:poof_admin/features/jobs/state/job_definition_form_notifier.dart';
import 'package:poof_admin/features/jobs/state/job_definition_form_state.dart';

/// Provider for the repository. Singleton.
final adminJobsRepositoryProvider = Provider<AdminJobsRepository>((ref) {
  // The AdminJobsRepository depends on the pmsApiProvider, which can be
  // either the mock or real API client depending on the flavor.
  return AdminJobsRepository(ref.read(pmsApiProvider));
});

/// Provider for the JobDefinition form.
final jobDefinitionFormProvider =
    StateNotifierProvider.autoDispose<JobDefinitionFormNotifier, JobDefinitionFormState>((ref) {
  return JobDefinitionFormNotifier(ref);
});