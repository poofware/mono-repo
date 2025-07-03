// lib/src/mixins/attestation_challenge_mixin.dart
//
// Shared helper for POST /challenge
// ──────────────────────────────────
// • Host class must expose:
//       String challengeBaseUrl   (e.g. authBaseUrl)
//       String get challengePath  (default ‘/challenge’)
//       bool   useRealAttestation
//   challenge, because the backend invalidates tokens after a single use.
//
// Mix this into both PublicApiMixin & AuthenticatedApiMixin.

mixin AttestationChallengeMixin {
  /* ------------------------------------------------------------------ */
  /*  Required by host class                                            */
  /* ------------------------------------------------------------------ */

  /// Base URL (scheme + host [+ port])
  String get attestationChallengeBaseUrl;

  /// Endpoint path; override if your backend differs.
  String get attestationChallengePath;

  /// Real vs dummy attestation mode.
  bool get useRealAttestation;
}

