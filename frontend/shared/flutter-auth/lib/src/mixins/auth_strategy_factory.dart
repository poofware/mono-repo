// flutter-auth/lib/src/mixins/auth_strategy_factory.dart
//
// 2025-06-25 - Updated to support the IoAuthStrategy refactor.
// • Removed `getAttestationChallenge` callback.
// • Added `challengePath` parameter to pass to `IoAuthStrategy`.

import 'package:flutter/foundation.dart' show kIsWeb;

import '../token_storage.dart';
import 'auth_strategy.dart';
import 'auth_strategy_io.dart';
import 'auth_strategy_web.dart';

AuthStrategy createAuthStrategy({
  required String baseUrl,
  required String authBaseUrl,
  required String refreshTokenPath,
  required String attestationChallengeBaseUrl,
  required String attestationChallengePath,
  required BaseTokenStorage tokenStorage,
  void Function()? onAuthLost,
  bool isRealAttestation = false,
}) {
  return kIsWeb
      ? WebAuthStrategy(
          baseUrl: baseUrl,
          authBaseUrl: authBaseUrl,
          refreshTokenPath: refreshTokenPath,
          onAuthLost: onAuthLost,
          isRealAttestation: isRealAttestation,
        )
      : IoAuthStrategy(
          baseUrl: baseUrl,
          refreshTokenBaseUrl: authBaseUrl,
          refreshTokenPath: refreshTokenPath,
          attestationChallengeBaseUrl: attestationChallengeBaseUrl,
          attestationChallengePath: attestationChallengePath,
          tokenStorage: tokenStorage,
          onAuthLost: onAuthLost,
          isRealAttestation: isRealAttestation,
        );
}
