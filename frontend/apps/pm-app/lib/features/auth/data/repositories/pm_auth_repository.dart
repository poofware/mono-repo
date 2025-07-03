import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_pm/features/auth/data/models/property_manager.dart';
import 'package:poof_pm/features/auth/data/models/pm_login_request.dart';
import 'package:poof_pm/features/auth/data/models/pm_register_request.dart';
import 'package:poof_pm/features/auth/data/api/pm_auth_api.dart';
import 'package:poof_pm/features/auth/state/pm_user_state_notifier.dart';

/// A PM-specific Auth Repository that orchestrates login, logout, refresh, etc.
/// Inherits from [BaseAuthRepository], and also updates the [PmUserStateNotifier]
/// so the app can track the currently logged-in PropertyManager.
class PmAuthRepository extends BaseAuthRepository<
    PropertyManager, PmLoginRequest, PmRegisterRequest> {
  final PmUserStateNotifier _pmUserNotifier;

  PmAuthRepository({
    required PmAuthApi authApi,
    required BaseTokenStorage tokenStorage,
    required PmUserStateNotifier pmUserNotifier,
  }) : _pmUserNotifier = pmUserNotifier,
       super(authApi: authApi, tokenStorage: tokenStorage);

  @override
  Future<PropertyManager> doLogin(PmLoginRequest credentials) async {
    final resp = await authApi.login(credentials);
    _pmUserNotifier.setPmUser(resp.user);
    return resp.user;
  }

  @override
  Future<void> doLogout() async {
    // 1) Base logout call => POST /pm/logout, clear tokens
    try {
      await authApi.logout(RefreshTokenRequest());
    } on ApiException catch (_) {
      /* ignore 401 / other errors on logout */
    }

    // 2) Also clear the local user state
    _pmUserNotifier.clearPmUser();
  }
}

