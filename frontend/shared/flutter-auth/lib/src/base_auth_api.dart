// flutter-auth/lib/src/base_auth_api.dart

import 'mixins/public_api_mixin.dart';
import 'mixins/authenticated_api_mixin.dart';
import 'models/models.dart';
import 'token_storage.dart';

abstract class BaseAuthApi<TUser, TLoginRequest extends JsonSerializable,
    TRegisterRequest extends JsonSerializable>
    with PublicApiMixin, AuthenticatedApiMixin {
  @override
  String get baseUrl;

  @override
  String get refreshTokenPath;

  @override
  String get refreshTokenBaseUrl => baseUrl;
  
  @override
  String get attestationChallengePath;

  @override
  String get attestationChallengeBaseUrl => baseUrl;

  @override
  BaseTokenStorage get tokenStorage;

  @override
  bool get useRealAttestation;

  // ------------------- AUTH API endpoints -------------------

  Future<bool> refreshTokensNow() => performTokenRefresh();

  Future<LoginResponseBase<TUser>> login(TLoginRequest request);

  Future<void> logout(RefreshTokenRequest request);

  Future<void> register(TRegisterRequest request);

  Future<void> checkEmailValid(CheckEmailRequest request);

  Future<void> checkPhoneValid(CheckPhoneRequest request);

  Future<TOTPSecretResponse> generateTOTPSecret();
  Future<void> requestEmailCode(EmailCodeRequest request);
  Future<void> verifyEmailCode(VerifyEmailCodeRequest request);
  Future<void> requestSMSCode(SMSCodeRequest request);
  Future<void> verifySMSCode(VerifySMSCodeRequest request);
}
