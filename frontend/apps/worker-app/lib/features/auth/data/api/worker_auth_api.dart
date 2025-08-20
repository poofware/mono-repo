import 'dart:convert';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/config/config.dart' show PoofWorkerFlavorConfig;
import 'package:poof_worker/features/account/data/models/models.dart';

import '../models/models.dart';

const String _v1 = '/v1';

/// Concrete implementation of the Worker Auth API.
/// Inherits from [BaseAuthApi], providing real or dummy attestation
/// based on [useRealAttestation].
///
/// We set `useRealAttestation` in the constructor by reading
/// PoofWorkerFlavorConfig.instance.testMode, or any other logic you want.
class WorkerAuthApi
    extends BaseAuthApi<Worker, LoginWorkerRequest, RegisterWorkerRequest> {
  @override
  final BaseTokenStorage tokenStorage;

  @override
  final void Function()? onAuthLost;

  /// We'll store this from the flavor config. If `testMode` is true,
  /// we do dummy attestation; if false, real.
  @override
  final bool useRealAttestation;

  // We can just reuse baseUrl for both public calls and refresh calls
  @override
  String get baseUrl => PoofWorkerFlavorConfig.instance.authServiceURL;

  @override
  String get refreshTokenPath => '$_v1/worker/refresh_token';

  @override
  String get attestationChallengePath => '$_v1/worker/challenge';

  WorkerAuthApi({
    required this.tokenStorage,
    this.onAuthLost,
  }) : useRealAttestation =
      PoofWorkerFlavorConfig.instance.realDeviceAttestation;

  // ----------------------------------------------------------------------
  //                           LOGIN
  // ----------------------------------------------------------------------
  /// POST /worker/login
  /// We override to ensure we do requireAttestation: true
  @override
  Future<LoginResponseBase<Worker>> login(LoginWorkerRequest request) async {
    final resp = await sendPublicRequest(
      method: 'POST',
      path: '$_v1/worker/login',
      body: request,
      requireAttestation: true, // <--- only for this endpoint
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final workerMap = decoded['worker'] as Map<String, dynamic>;
    final worker = Worker.fromJson(workerMap);

    return LoginResponseBase<Worker>(
      user: worker,
      accessToken: decoded['access_token'] as String,
      refreshToken: decoded['refresh_token'] as String,
    );
  }

  // ----------------------------------------------------------------------
  //                           LOGOUT
  // ----------------------------------------------------------------------
  @override
  Future<void> logout(RefreshTokenRequest request) async {
    // We do NOT attempt refresh on 401 => `attemptRefreshOn401: false`.
    // No attestation needed here, so `requireAttestation: false` is fine.
    await sendAuthenticatedRequest(
      method: 'POST',
      path: '$_v1/worker/logout',
      body: request,
      attemptRefreshOn401: false,
      requireAttestation: false,
    );
  }

  // ----------------------------------------------------------------------
  //                           REGISTER
  // ----------------------------------------------------------------------
  /// POST /worker/register
  /// Registration typically doesn't need attestation, so pass false.
  @override
  Future<void> register(RegisterWorkerRequest request) async {
    await sendPublicRequest(
      method: 'POST',
      path: '$_v1/worker/register',
      body: request,
      requireAttestation: false,
    );
  }

  // ----------------------------------------------------------------------
  //                   VALIDATE (replaces "exists")
  // ----------------------------------------------------------------------
  @override
  Future<void> checkEmailValid(CheckEmailRequest request) async {
    await sendPublicRequest(
      method: 'POST',
      path: '$_v1/worker/email/valid',
      body: request,
      requireAttestation: false,
    );
  }

  @override
  Future<void> checkPhoneValid(CheckPhoneRequest request) async {
    await sendPublicRequest(
      method: 'POST',
      path: '$_v1/worker/phone/valid',
      body: request,
      requireAttestation: false,
    );
  }

  // ----------------------------------------------------------------------
  //                   TOTP + VERIFICATION ENDPOINTS
  // ----------------------------------------------------------------------
  @override
  Future<TOTPSecretResponse> generateTOTPSecret() async {
    final resp = await sendPublicRequest(
      method: 'POST',
      path: '/$_v1/register/totp_secret',
      requireAttestation: false,
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    return TOTPSecretResponse.fromJson(decoded);
  }

  @override
  Future<void> requestEmailCode(EmailCodeRequest request) async {
    // This endpoint can be called by both authenticated (profile update) and
    // unauthenticated (new registration) users. We check for tokens to decide.
    final tokens = await tokenStorage.getTokens();
    if (tokens != null) {
      // User is likely logged in, send an authenticated request.
      await sendAuthenticatedRequest(
        method: 'POST',
        path: '$_v1/worker/request_email_code',
        body: request,
      );
    } else {
      // User is not logged in, send a public request.
      await sendPublicRequest(
          method: 'POST', path: '$_v1/worker/request_email_code', body: request);
    }
  }

  @override
  Future<void> verifyEmailCode(VerifyEmailCodeRequest request) async {
    // This endpoint can be called by both authenticated (profile update) and
    // unauthenticated (new registration) users. We check for tokens to decide.
    final tokens = await tokenStorage.getTokens();
    if (tokens != null) {
      // User is likely logged in, send an authenticated request.
      await sendAuthenticatedRequest(
        method: 'POST',
        path: '$_v1/worker/verify_email_code',
        body: request,
      );
    } else {
      // User is not logged in, send a public request.
      await sendPublicRequest(
        method: 'POST',
        path: '$_v1/worker/verify_email_code',
        body: request,
      );
    }
  }

  @override
  Future<void> requestSMSCode(SMSCodeRequest request) async {
    // This endpoint can be called by both authenticated (profile update) and
    // unauthenticated (new registration) users. We check for tokens to decide.
    final tokens = await tokenStorage.getTokens();
    if (tokens != null) {
      // User is likely logged in, send an authenticated request.
      await sendAuthenticatedRequest(
        method: 'POST',
        path: '$_v1/worker/request_sms_code',
        body: request,
      );
    } else {
      // User is not logged in, send a public request.
      await sendPublicRequest(
          method: 'POST', path: '$_v1/worker/request_sms_code', body: request);
    }
  }

  @override
  Future<void> verifySMSCode(VerifySMSCodeRequest request) async {
    // This endpoint can be called by both authenticated (profile update) and
    // unauthenticated (new registration) users. We check for tokens to decide.
    final tokens = await tokenStorage.getTokens();
    if (tokens != null) {
      // User is likely logged in, send an authenticated request.
      await sendAuthenticatedRequest(
        method: 'POST',
        path: '$_v1/worker/verify_sms_code',
        body: request,
      );
    } else {
      // User is not logged in, send a public request.
      await sendPublicRequest(
        method: 'POST',
        path: '$_v1/worker/verify_sms_code',
        body: request,
      );
    }
  }
}
