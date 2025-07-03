// flutter-auth/lib/src/utils/attestation_helper.dart
//
// 2025-06-27 – Updates  
// • Validates challenge size (32 bytes) and normalises Base64.  
// • Surfaces `unsupportedOS` and other PlatformExceptions up through
//   `getAttestationHeaders`.  
// • Adds detailed logging comments for future maintainers.  
//
// 2025-07-02 – **Concurrency patch**  
// • Serialises *all* **real** device-attestation calls with a single,
//   isolate-wide mutex from the `synchronized` package so that only one native
//   Play-Integrity/App Attest invocation can be in flight at a time. :contentReference[oaicite:0]{index=0}

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:synchronized/synchronized.dart';        // ← new
import '../exceptions/api_exceptions.dart';
import '../models/models.dart';
import '../utils/header_utils.dart';
import '../utils/request_utils.dart';
import '../utils/platform_utils.dart';
import '../utils/device_attestation_utils.dart' as attestation;

/// Helper that owns the full challenge → attestation → header assembly flow.
class AttestationHelper {
  final String challengeBaseUrl;
  final String challengePath;
  final bool useRealAttestation;

  /// Global, isolate-wide mutex that ensures **only one** real attestation runs
  /// at a time.  Re-entrant so a caller already inside the critical section
  /// can re-enter without dead-locking.
  static final Lock _attestationLock = Lock(reentrant: true);

  AttestationHelper({
    required this.challengeBaseUrl,
    required this.challengePath,
    required this.useRealAttestation,
  });

  /// Performs the full attestation flow and returns ready-to-inject headers.
  ///
  /// * Web / unknown platforms → `{}` (no attestation).  
  /// * Dummy mode (`useRealAttestation == false`) → fake headers for CI/dev.  
  /// * Real mode → serialised native attestation guarded by `_attestationLock`.
  Future<Map<String, String>> getAttestationHeaders() async {
    final platform = getCurrentPlatform();
    if (platform == FlutterPlatform.web ||
        platform == FlutterPlatform.unknown) {
      return {}; // Only mobile is supported.
    }

    // --- Dummy flow (no locking needed) ------------------------------------
    if (!useRealAttestation) {
      return {
        'X-Device-Integrity': 'FAKE_INTEGRITY_TOKEN',
        'X-Key-Id':
            platform == FlutterPlatform.android ? 'FAKE-PLAY' : 'FAKE-IOS',
      };
    }

    // --- Real flow: everything is serialised under the mutex ---------------
    return _attestationLock.synchronized(() async {
      // 1. Obtain challenge from backend.
      final ChallengeResponse challengeResp =
          await _getChallenge(platform.name);

      // 2. Extra integrity: verify challenge length (32 bytes).
      final decodedNonce =
          base64Url.decode(base64.normalize(challengeResp.challenge));
      if (decodedNonce.length != 32) {
        throw ApiException(
          'Backend challenge length invalid: expected 32 bytes, got '
          '${decodedNonce.length}',
          errorCode: 'invalid_challenge_size',
        );
      }

      try {
        // 3. Perform OS-level attestation to get raw components.
        final Map<String, dynamic> components =
            await attestation.performDeviceAttestation(
          isAndroid: platform == FlutterPlatform.android,
          isRealAttestation: true,
          challengeToken: challengeResp.challengeToken,
          challengeString: challengeResp.challenge,
        );

        // 4. Build payload.
        final payload = AttestationPayload(
          challengeToken: challengeResp.challengeToken,
          integrityToken: components['integrity_token'] as String?,
          keyId: components['key_id'] as String?,
          attestation: components['attestation'] as String?,
          assertion: components['assertion'] as String?,
          clientData: components['client_data'] as String?,
        );

        final String encodedPayload =
            base64.encode(utf8.encode(json.encode(payload.toJson())));

        // 5. Construct headers.
        final headers = <String, String>{
          'X-Device-Integrity': encodedPayload,
        };
        if (components['key_id'] != null) {
          headers['X-Key-Id'] = components['key_id'] as String;
        }
        return headers;
      } on http.ClientException catch (e) {
        // Network issues.
        throw ApiException(
          'Network error during attestation: ${e.message}',
          errorCode: 'network_error',
        );
      } on Exception {
        // Bubble up PlatformExceptions (e.g., unsupportedOS) untouched so
        // callers can decide whether to fall back or surface to the user.
        rethrow;
      }
    });
  }

  /* ─────────────────── Internal helpers ─────────────────── */

  /// Fetches the challenge from the backend.
  Future<ChallengeResponse> _getChallenge(String platform) async {
    if (!useRealAttestation) {
      return ChallengeResponse(
        challengeToken: 'dummy-challenge-token',
        // 32 random bytes, base64-url encoded
        challenge: base64Url.encode(Uint8List(32)),
      );
    }

    final uri = Uri.parse('$challengeBaseUrl$challengePath');
    final headers = <String, String>{'Content-Type': 'application/json'};
    final body = jsonEncode(ChallengeRequest(platform).toJson());

    await injectMobileHeaders(headers: headers, includeDeviceId: true);

    final http.Response resp = await doHttp('POST', uri, headers, body);

    if (resp.statusCode >= 400) {
      throw ApiException.fromHttpResponse(resp.statusCode, resp.body);
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    return ChallengeResponse.fromJson(decoded);
  }
}

