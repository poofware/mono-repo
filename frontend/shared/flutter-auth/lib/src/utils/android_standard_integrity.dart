import 'package:flutter/services.dart';

class StandardIntegrity {
  static const _ch = MethodChannel('standard_integrity');

  Future<String> getToken(
      String requestHashB64Url, int gcpProjectNumber) async {
    final jws = await _ch.invokeMethod<String>(
      'getStandardIntegrityToken',
      {
        'requestHash': requestHashB64Url,
        'gcpProjectNumber': gcpProjectNumber,
      },
    );
    if (jws == null || jws.isEmpty) {
      throw StateError('Play Integrity returned empty JWS');
    }
    return jws;
  }
}

