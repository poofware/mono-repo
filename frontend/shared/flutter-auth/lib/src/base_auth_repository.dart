import 'exceptions/api_exceptions.dart';
import 'token_storage.dart';
import 'models/models.dart';
import 'base_auth_api.dart';

/// A generic Auth Repository that coordinates higher-level login/register/logout
/// flows.  Child classes can override the high-level methods and optionally call
/// `super` to retain the common behaviour (saving / clearing tokens, etc.).
abstract class BaseAuthRepository<
    TUser,
    TLoginRequest extends JsonSerializable,
    TRegisterRequest extends JsonSerializable> {
  final BaseAuthApi<TUser, TLoginRequest, TRegisterRequest> authApi;
  final BaseTokenStorage tokenStorage;

  BaseAuthRepository({
    required this.authApi,
    required this.tokenStorage,
  });

  /// Checks if we have tokens locally (i.e. the user may be “logged in”).
  Future<bool> hasTokens() async => (await tokenStorage.getTokens()) != null;

  // ────────────────────────────────────────────────────────────────
  //  LOGIN  – returns the freshly logged-in user so children can
  //  perform any extra state updates without duplicating code.
  // ────────────────────────────────────────────────────────────────
  Future<TUser> doLogin(TLoginRequest credentials) async {
    final resp = await authApi.login(credentials);
    await tokenStorage.saveTokens(
      TokenPair(
        accessToken: resp.accessToken!,
        refreshToken: resp.refreshToken!,
      ),
    );
    return resp.user;
  }

  /// Explicit refresh helper (mostly used by SessionManager).
  Future<void> doRefreshToken() async {
    final bool ok = await authApi.refreshTokensNow();
    if (!ok) {
      throw ApiException('Failed to refresh tokens', errorCode: 'refresh_failed');
    }
  }

  // ────────────────────────────────────────────────────────────────
  //  LOGOUT  – clears tokens; children can call super then do extras
  // ────────────────────────────────────────────────────────────────
  Future<void> doLogout() async {
    final tokens = await tokenStorage.getTokens();
    if (tokens == null) return;

    try {
      await authApi.logout(RefreshTokenRequest(refreshToken: tokens.refreshToken));
    } on ApiException catch (_) {
      /* ignore 401 / other errors on logout */
    }

    await tokenStorage.clearTokens();
  }

  // -------------- "Valid" endpoints + TOTP + verification --------------
  ///
  /// NEW: Replaces old "checkEmailExists", now "checkEmailValid" returns `void`:
  ///  - Succeeds if 200 from the server (email is unused/valid).
  ///  - Throws on 409 or other error statuses.
  Future<void> checkEmailValid(String email) =>
      authApi.checkEmailValid(CheckEmailRequest(email));

  ///
  /// NEW: Replaces old "checkPhoneExists", now "checkPhoneValid" returns `void`:
  ///  - Succeeds if 200 from the server (phone is unused/valid).
  ///  - Throws on 409 or other error statuses.
  Future<void> checkPhoneValid(String phone) =>
      authApi.checkPhoneValid(CheckPhoneRequest(phone));

  Future<TOTPSecretResponse> generateTOTPSecret() =>
      authApi.generateTOTPSecret();

  Future<void> requestEmailCode(String email) =>
      authApi.requestEmailCode(EmailCodeRequest(email));

  Future<void> verifyEmailCode(String email, String code) =>
      authApi.verifyEmailCode(VerifyEmailCodeRequest(email: email, code: code));

  Future<void> requestSMSCode(String phone) =>
      authApi.requestSMSCode(SMSCodeRequest(phone));

  Future<void> verifySMSCode(String phone, String code) =>
      authApi.verifySMSCode(VerifySMSCodeRequest(phoneNumber: phone, code: code));

  /// Concrete repositories implement their own registration call.
  Future<void> doRegister(TRegisterRequest data) => authApi.register(data);
}

