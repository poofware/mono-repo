// lib/poof_flutter_auth/src/device_id_manager.dart

import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_udid/flutter_udid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceIdManager {
  static const _deviceIdKey = 'poof_device_id';
  static final _storage = const FlutterSecureStorage();

  /// Returns the stable hashed device ID, generating it once if missing.
  static Future<String> getDeviceId() async {
    // 1) Check if already in secure storage
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null) {
      return existing;
    }

    // 2) If not found, generate new:
    final rawUdid = await FlutterUdid.udid;
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    // Combine them, then hash with SHA-256
    final combined = rawUdid + timestamp;
    final hashed = _sha256String(combined);

    // 3) Save to secure storage for future calls
    await _storage.write(key: _deviceIdKey, value: hashed);
    return hashed;
  }

  static String _sha256String(String input) {
    final bytes = utf8.encode(input);
    final digest = crypto.sha256.convert(bytes);
    // Return hex string of the hash
    return digest.toString();
  }
}

