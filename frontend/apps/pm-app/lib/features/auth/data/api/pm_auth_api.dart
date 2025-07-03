import 'dart:convert';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_pm/core/config/flavors.dart';
import '../models/pm_login_request.dart';
import '../models/pm_register_request.dart';
import '../models/property_manager.dart';

/// Concrete implementation of the PM Auth API.
/// Inherits from [BaseAuthApi], providing the same device attestation
/// pattern but focusing on "pm" endpoints like `/pm/login`, `/pm/register`.
class PmAuthApi extends BaseAuthApi<PropertyManager, PmLoginRequest, PmRegisterRequest> {
  @override
  final BaseTokenStorage tokenStorage;

  @override
  final void Function()? onAuthLost;

  @override
  final bool useRealAttestation;

  // We can just reuse [baseUrl] for public and authenticated requests
  @override
  String get baseUrl => PoofPMFlavorConfig.instance.authServiceURL;

  /// For PM, we'll also do refresh at the same `authServiceURL`.
  @override
  String get refreshTokenPath => '/pm/refresh_token';

  @override
  String get attestationChallengePath => '';

  PmAuthApi({
    required this.tokenStorage,
    this.onAuthLost,
    this.useRealAttestation = false,
  });

  // -------------------------------------------
  // LOGIN
  // -------------------------------------------
  /// POST /pm/login
  @override
  Future<LoginResponseBase<PropertyManager>> login(PmLoginRequest request) async {
    final resp = await sendPublicRequest(
      method: 'POST',
      path: '/pm/login',
      body: request,
      requireAttestation: false, // typically for web
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final pmMap = decoded['pm'] as Map<String, dynamic>;
    final pmUser = PropertyManager.fromJson(pmMap);

    return LoginResponseBase<PropertyManager>(
      user: pmUser,
    );
  }

  // -------------------------------------------
  // LOGOUT
  // -------------------------------------------
  @override
  Future<void> logout(RefreshTokenRequest request) async {
    // No refresh attempt on 401 for logout
    await sendAuthenticatedRequest(
      method: 'POST',
      path: '/pm/logout',
      body: request,
      attemptRefreshOn401: false,
      requireAttestation: false,
    );
  }

  // -------------------------------------------
  // REGISTER
  // -------------------------------------------
  /// POST /pm/register
  @override
  Future<void> register(PmRegisterRequest request) async {
    await sendPublicRequest(
      method: 'POST',
      path: '/pm/register',
      body: request,
      requireAttestation: false,
    );
  }

  // -------------------------------------------
  // Email/Phone "valid" checks
  // -------------------------------------------
  @override
  Future<void> checkEmailValid(CheckEmailRequest request) async {
    await sendPublicRequest(
      method: 'POST',
      path: '/pm/email/valid',
      body: request,
      requireAttestation: false,
    );
  }

  @override
  Future<void> checkPhoneValid(CheckPhoneRequest request) async {
    await sendPublicRequest(
      method: 'POST',
      path: '/pm/phone/valid',
      body: request,
      requireAttestation: false,
    );
  }

  // -------------------------------------------
  // TOTP + Verification Endpoints
  // -------------------------------------------
  @override
  Future<TOTPSecretResponse> generateTOTPSecret() async {
    final resp = await sendPublicRequest(
      method: 'POST',
      path: '/register/totp_secret',
      requireAttestation: false,
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    return TOTPSecretResponse.fromJson(decoded);
  }

  @override
  Future<void> requestEmailCode(EmailCodeRequest request) async {
    await sendPublicRequest(
      method: 'POST',
      path: '/pm/request_email_code',
      body: request,
      requireAttestation: false,
    );
  }

  @override
  Future<void> verifyEmailCode(VerifyEmailCodeRequest request) async {
    await sendPublicRequest(
      method: 'POST',
      path: '/pm/verify_email_code',
      body: request,
      requireAttestation: false,
    );
  }

  @override
  Future<void> requestSMSCode(SMSCodeRequest request) async {
    // For PM, phone is optional but if used, same pattern:
    await sendPublicRequest(
      method: 'POST',
      path: '/pm/request_sms_code',
      body: request,
      requireAttestation: false,
    );
  }

  @override
  Future<void> verifySMSCode(VerifySMSCodeRequest request) async {
    await sendPublicRequest(
      method: 'POST',
      path: '/pm/verify_sms_code',
      body: request,
      requireAttestation: false,
    );
  }
}
