// frontend/apps/admin-app/integration_test/api/test_context.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/account/data/repositories/admin_account_repository.dart';
import 'package:poof_admin/features/auth/data/repositories/admin_auth_repository.dart';
import 'package:poof_admin/features/jobs/data/repositories/admin_jobs_repository.dart';

/// A simple static class to hold shared instances across test files.
/// This avoids re-instantiating providers and ensures the authenticated
/// state persists from the auth test to the feature tests.
class TestContext {
  static final container = ProviderContainer();
  static AdminAuthRepository? authRepo;
  static AdminAccountRepository? accountRepo;
  static AdminJobsRepository? jobsRepo;
}