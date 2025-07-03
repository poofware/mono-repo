// flutter-auth/lib/src/utils/device_attestation_utils.dart
//
// REAL Android → **Standard** Play Integrity (attestation = integrity_token, att = "play")
// REAL iOS     → App Attest      (attestation = key_id + attestation OR assertion)
//
// DUMMY branch still returns “FAKE_*” so CI/dev builds keep working.
//
// 2025‑06‑30 – rev 4
// • Android path now calls our MethodChannel wrapper (`StandardIntegrity`) that
//   uses the Standard API. The server already provides a hashed challenge.
// • `app_device_integrity` is kept only for iOS flows.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:app_device_integrity/app_device_integrity.dart';
import 'package:crypto/crypto.dart';
import 'package:device_check/device_check.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'android_standard_integrity.dart' as std_integrity;

const _kGcpProjectNumber = '1084456625514';
const _kIosKeyIdStorage = '_poof_ios_appattest_key_id';

final _secure = const FlutterSecureStorage();
// Used only for iOS
final _appIntegrity = AppDeviceIntegrity();

/// Performs device attestation and returns a map of raw components for the final payload.
Future<Map<String, dynamic>> performDeviceAttestation({
  required bool isAndroid,
  required bool isRealAttestation,
  required String challengeToken,
  required String challengeString,
}) async {
  /* ───────── OS-level pre-flight ────────────────────────────────────────── */
  await _ensureSupportedPlatform(isAndroid: isAndroid);

  /* ───────── Dummy branch ───────────────────────────────────────────────── */
  if (!isRealAttestation) {
    return {
      'integrity_token': 'FAKE_INTEGRITY_TOKEN',
      'key_id': isAndroid ? 'FAKE-PLAY' : 'FAKE-IOS',
    };
  }

  /* ───────── Android path: Play Integrity (Standard API) ────────────────── */
  if (isAndroid) {
    // Server already supplied Base64‑URL SHA‑256 hash → forward unchanged
    final integrityJws = await std_integrity.StandardIntegrity().getToken(
      challengeString,
      int.parse(_kGcpProjectNumber),
    );

    return {
      'integrity_token': integrityJws,
      'key_id': 'play',
    };
  }

  /* ───────── iOS path: App Attest ───────────────────────────────────────── */
  return _performIosAppAttest(challengeString);
}

/* ────────────────────────────────────────────────────────────────────────── */
/* Helper: iOS App Attest                                                   */
/* ────────────────────────────────────────────────────────────────────────── */
Future<Map<String, dynamic>> _performIosAppAttest(
    String challengeString) async {
  if (!await AppAttestService.instance.isSupported()) {
    throw PlatformException(
      code: 'appAttestUnavailable',
      message:
          'This device does not support App Attest or the capability is missing.',
    );
  }

  final decodedNonce = base64Url.decode(base64.normalize(challengeString));
  if (decodedNonce.length != 32) {
    throw PlatformException(
      code: 'invalidChallengeSize',
      message: 'App Attest nonce must be 32 bytes; got ${decodedNonce.length}.',
    );
  }

  final storedKeyId = await _secure.read(key: _kIosKeyIdStorage);

  /* ----- ASSERTION FLOW (key already stored) ----------------------------- */
  if (storedKeyId != null && storedKeyId.isNotEmpty) {
    try {
      final clientData = jsonEncode({'challenge': challengeString});
      final clientDataBytes = utf8.encode(clientData);

      final clientDataHash = sha256.convert(clientDataBytes).bytes;

      final assertionBytes = await AppAttestService.instance.generateAssertion(
        keyId: storedKeyId,
        clientDataHash: Uint8List.fromList(clientDataHash),
      );

      return {
        'key_id': storedKeyId,
        'assertion': base64Url.encode(assertionBytes),
        'client_data': base64Url.encode(clientDataBytes),
      };
    } on PlatformException catch (e) {
      const invalidKeyCodes = {
        '2',
        'com.apple.devicecheck.error 2',
        'invalidKey',
        'invalidInput',
      };
      if (invalidKeyCodes.contains(e.code)) {
        await _secure.delete(key: _kIosKeyIdStorage);
      } else {
        rethrow;
      }
    }
  }

  /* ----- ATTESTATION FLOW (no key or key was invalid) -------------------- */
  final attestationResultJson = await _appIntegrity.getAttestationServiceSupport(
        challengeString: challengeString,
      ) ??
      (throw PlatformException(
        code: 'attestationNull',
        message: 'App Attest returned a null response.',
      ));

  final Map<String, dynamic> decoded = jsonDecode(attestationResultJson);
  final newKeyId = decoded['keyID'] as String?;

  if (newKeyId != null && newKeyId.isNotEmpty) {
    await _secure.write(key: _kIosKeyIdStorage, value: newKeyId);
  }

  final clientData = jsonEncode({'challenge': challengeString});
  final clientDataBytes = utf8.encode(clientData);

  return {
    'key_id': newKeyId,
    if (decoded.containsKey('attestationString'))
      'attestation': decoded['attestationString'],
    if (decoded.containsKey('assertionString'))
      'assertion': decoded['assertionString'],
    'client_data': base64Url.encode(clientDataBytes),
  };
}

/* ────────────────────────────────────────────────────────────────────────── */
/* Helper: OS/version guards                                                */
/* ────────────────────────────────────────────────────────────────────────── */
Future<void> _ensureSupportedPlatform({required bool isAndroid}) async {
  if (isAndroid) {
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    if (sdk < 21) {
      throw PlatformException(
        code: 'unsupportedOS',
        message: 'Play Integrity requires Android 5.0 (API 21) or later.',
      );
    }
  } else {
    final match =
        RegExp(r'(\d+)\.(\d+)').firstMatch(Platform.operatingSystemVersion);
    final major = match != null ? int.tryParse(match.group(1)!) : null;
    if (major == null || major < 14) {
      throw PlatformException(
        code: 'unsupportedOS',
        message: 'App Attest requires iOS 14 or later.',
      );
    }
  }
}

/// Returns cached key ID (`"play"` for Android).
Future<String?> getCachedKeyId({required bool isAndroid}) {
  return isAndroid
      ? Future.value('play')
      : _secure.read(key: _kIosKeyIdStorage);
}

Future<void> clearIosKeyId() async {
  await _secure.delete(key: _kIosKeyIdStorage);
}

