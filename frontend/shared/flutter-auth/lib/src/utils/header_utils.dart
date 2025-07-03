// lib/src/utils/header_utils.dart
//
// 2025-06-25 – Simplified
// • injectMobileHeaders is now *baseline-only*: it adds
//     ─ X-Platform
//     ─ X-Device-ID       (optional)
// • All attestation headers (X-Device-Integrity, X-Key-Id) are injected by
//   the higher-level helpers (`_attachAttestationHeaders` in IoAuthStrategy,
//   or `sendPublicRequest` for unauthenticated flows).
//
// The signature is kept unchanged so existing call-sites compile, but
//   – `requireAttestation` and `isRealAttestation` are now *ignored*.

import 'device_id_manager.dart';
import 'platform_utils.dart';
import 'device_attestation_utils.dart' as attestation;

/// Adds platform / device-ID headers for **Android** and **iOS** clients.
///
/// - `X-Platform`  → "android" or "ios"
/// - `X-Device-ID` → stable SHA-256 hash (if [includeDeviceId] == true)
///
/// Attestation headers are *not* handled here anymore; those are injected
/// by the surrounding strategy/helpers after this baseline call completes.
Future<void> injectMobileHeaders({
  required Map<String, String> headers,
  required bool includeDeviceId,
}) async {
  final platform = getCurrentPlatform();

  switch (platform) {
    case FlutterPlatform.android:
      headers['X-Platform'] = 'android';
      break;
    case FlutterPlatform.ios:
      headers['X-Platform'] = 'ios';
      break;
    default:
      throw StateError(
        'injectMobileHeaders called on unsupported platform: $platform',
      );
  }

  if (includeDeviceId) {
    final deviceId = await DeviceIdManager.getDeviceId();
    headers['X-Device-ID'] = deviceId;
  }

  // Always include the Key ID if we have one cached. This ensures that
  // tokens containing an 'att' claim can always be validated.
  final keyId = await attestation.getCachedKeyId(
    isAndroid: platform == FlutterPlatform.android,
  );
  if (keyId != null && keyId.isNotEmpty) {
    headers['X-Key-Id'] = keyId;
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  WEB-ONLY helper (unchanged)
// ─────────────────────────────────────────────────────────────────────────

/// Adds `"X-Platform": "web"` and, if the target host contains “ngrok”,
/// adds `ngrok-skip-browser-warning: true` to silence the banner.
void injectWebHeaders({
  required Map<String, String> headers,
  required Uri url,
}) {
    headers['X-Platform'] = 'web';
    if (url.host.toLowerCase().contains('ngrok')) {
      headers['ngrok-skip-browser-warning'] = 'true';
    }
}

