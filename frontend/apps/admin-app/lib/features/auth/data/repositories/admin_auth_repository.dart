// NEW FILE
import 'package:poof_admin/features/auth/data/api/admin_auth_api.dart';
import 'package:poof_admin/features/auth/data/models/admin.dart';
import 'package:poof_admin/features/auth/data/models/admin_login_request.dart';
import 'package:poof_admin/features/auth/state/admin_user_state_notifier.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';

class AdminAuthRepository extends BaseAuthRepository<Admin, AdminLoginRequest, JsonSerializable> {
  final AdminUserStateNotifier _adminUserNotifier;

  AdminAuthRepository({
    required AdminAuthApi authApi,
    required BaseTokenStorage tokenStorage,
    required AdminUserStateNotifier adminUserNotifier,
  })  : _adminUserNotifier = adminUserNotifier,
        super(authApi: authApi, tokenStorage: tokenStorage);

  @override
  Future<Admin> doLogin(AdminLoginRequest credentials) async {
    final resp = await authApi.login(credentials);
    _adminUserNotifier.setAdminUser(resp.user);
    return resp.user;
  }

  @override
  Future<void> doLogout() async {
    try {
      await authApi.logout(RefreshTokenRequest());
    } on ApiException catch (_) {
      // Ignore errors on logout
    }
    _adminUserNotifier.clearAdminUser();
  }
}