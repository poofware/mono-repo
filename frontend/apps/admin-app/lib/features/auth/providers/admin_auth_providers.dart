// NEW FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/core/config/flavors.dart';
import 'package:poof_admin/core/providers/auth_controller_provider.dart';
import 'package:poof_admin/features/auth/data/api/admin_auth_api.dart';
import 'package:poof_admin/features/auth/data/repositories/admin_auth_repository.dart';
import 'package:poof_admin/features/auth/state/admin_auth_state.dart';
import 'package:poof_admin/features/auth/state/admin_auth_state_notifier.dart';
import 'package:poof_admin/features/auth/state/admin_user_state.dart';
import 'package:poof_admin/features/auth/state/admin_user_state_notifier.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';

/// 1. Token storage for Admin (web uses NoOp)
final adminTokenStorageProvider = Provider<BaseTokenStorage>((ref) {
  return NoOpTokenStorage();
});

/// 2. The Admin Auth API client
final adminAuthApiProvider = Provider<AdminAuthApi>((ref) {
  final tokenStorage = ref.read(adminTokenStorageProvider);
  return AdminAuthApi(
    tokenStorage: tokenStorage,
    useRealAttestation: PoofAdminFlavorConfig.instance.testMode == false,
   // onAuthLost: () => ref.read(authControllerProvider).handleAuthLost(),
  );
});

/// 3. StateNotifier for the currently logged-in Admin user object
final adminUserStateNotifierProvider =
    StateNotifierProvider<AdminUserStateNotifier, AdminUserState>(
  (_) => AdminUserStateNotifier(),
);

/// 4. The Admin Auth Repository
final adminAuthRepositoryProvider = Provider<AdminAuthRepository>((ref) {
  final api = ref.read(adminAuthApiProvider);
  final tokenStorage = ref.read(adminTokenStorageProvider);
  final userNotifier = ref.read(adminUserStateNotifierProvider.notifier);
  return AdminAuthRepository(
    authApi: api,
    tokenStorage: tokenStorage,
    adminUserNotifier: userNotifier,
  );
});

/// 5. StateNotifier to hold ephemeral credentials between login pages
final adminAuthStateNotifierProvider =
    StateNotifierProvider<AdminAuthStateNotifier, AdminAuthState>(
  (_) => AdminAuthStateNotifier(),
);