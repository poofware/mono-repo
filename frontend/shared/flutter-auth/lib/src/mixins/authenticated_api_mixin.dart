// flutter-auth/lib/src/mixins/authenticated_api_mixin.dart
//
// 2025-06-25 - No breaking changes.
// • Updated to pass `challengePath` to the `createAuthStrategy` factory
//   so `IoAuthStrategy` can construct its own `AttestationHelper`.
// • Removed the now-unused `getAttestationChallenge` parameter.

import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../token_storage.dart';
import 'auth_strategy.dart';
import 'auth_strategy_factory.dart';
import 'attestation_challenge_mixin.dart';

mixin AuthenticatedApiMixin implements AttestationChallengeMixin {
  /* ───── properties concrete API classes must provide ───── */
  String get baseUrl;
  String get refreshTokenBaseUrl;
  String get refreshTokenPath;
  BaseTokenStorage get tokenStorage;

  /// Called when refresh fails (optional).
  void Function()? get onAuthLost => null;

  /* ───── instantiated once, then reused ───── */
  late final AuthStrategy _authStrategy = createAuthStrategy(
    baseUrl: baseUrl,
    authBaseUrl: refreshTokenBaseUrl,
    refreshTokenPath: refreshTokenPath,
    attestationChallengeBaseUrl: attestationChallengeBaseUrl,
    attestationChallengePath: attestationChallengePath,
    tokenStorage: tokenStorage,
    onAuthLost: onAuthLost,
    isRealAttestation: useRealAttestation,
  );

  /// Sends an authenticated JSON request using the chosen strategy.
  ///
  /// [requireAttestation] can be set to `true` for endpoints that need
  /// a device attestation header. Defaults to false for typical endpoints.
  Future<http.Response> sendAuthenticatedRequest({
    required String method,
    required String path,
    JsonSerializable? body,
    bool attemptRefreshOn401 = true,
    bool requireAttestation = false,
  }) =>
      _authStrategy.sendAuthenticatedRequest(
        method: method,
        path: path,
        body: body,
        attemptRefreshOn401: attemptRefreshOn401,
        requireAttestation: requireAttestation,
      );

  /// Similarly for multipart requests
  Future<http.Response> sendAuthenticatedMultipartRequest({
    String method = 'POST',
    required String path,
    Map<String, String>? fields,
    List<Object>? files,
    bool attemptRefreshOn401 = true,
    bool requireAttestation = false,
  }) =>
      _authStrategy.sendAuthenticatedMultipartRequest(
        method: method,
        path: path,
        fields: fields,
        files: files,
        attemptRefreshOn401: attemptRefreshOn401,
        requireAttestation: requireAttestation,
      );

  /// Explicit refresh helper.
  Future<bool> performTokenRefresh() =>
      _authStrategy.performTokenRefresh();
}
