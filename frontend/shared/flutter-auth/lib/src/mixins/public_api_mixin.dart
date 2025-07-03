// flutter-auth/lib/src/mixins/public_api_mixin.dart

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'attestation_challenge_mixin.dart';
import '../exceptions/api_exceptions.dart';
import '../models/models.dart';
import '../utils/header_utils.dart' as header_utils;
import '../utils/request_utils.dart';
import '../utils/attestation_helper.dart';
import '../utils/device_attestation_utils.dart' as attestation;

mixin PublicApiMixin implements AttestationChallengeMixin {
  String get baseUrl;

  late final _attestationHelper = AttestationHelper(
    challengeBaseUrl: attestationChallengeBaseUrl,
    challengePath: attestationChallengePath,
    useRealAttestation: useRealAttestation,
  );

  /// Executes an HTTP request, handling the re-attestation retry logic for iOS.
  Future<http.Response> _executeRequestWithRetry(
    String method,
    Uri url,
    JsonSerializable? body,
    bool requireAttestation,
  ) async {
    final headers = <String, String>{'Content-Type': 'application/json'};

    // Build baseline and (optional) initial attestation headers.
    if (kIsWeb) {
      header_utils.injectWebHeaders(headers: headers, url: url);
    } else {
      await header_utils.injectMobileHeaders(headers: headers, includeDeviceId: true);
      if (requireAttestation) {
        final attestationHeaders = await _attestationHelper.getAttestationHeaders();
        headers.addAll(attestationHeaders);
      }
    }

    final encodedBody = body == null ? null : jsonEncode(body.toJson());

    try {
      // First attempt
      final response = await doHttp(method, url, headers, encodedBody);

      // CRITICAL FIX: Check for an error status and throw the exception *inside* the try block.
      if (response.statusCode >= 400) {
        throw ApiException.fromHttpResponse(response.statusCode, response.body);
      }
      return response;
    } on ApiException catch (e) {
      // The catch block can now correctly inspect the ApiException.
      if (e.errorCode == 'key_not_found_for_assertion') {
        // Clear the stale key and get fresh headers. This will now perform a full attestation.
        await attestation.clearIosKeyId();
        final newAttestationHeaders = await _attestationHelper.getAttestationHeaders();
        headers.addAll(newAttestationHeaders); // Add the new headers to our existing map

        // Retry the request once. This must also be checked for errors.
        final retryResponse = await doHttp(method, url, headers, encodedBody);
        if (retryResponse.statusCode >= 400) {
          throw ApiException.fromHttpResponse(retryResponse.statusCode, retryResponse.body);
        }
        return retryResponse;
      }
      // For any other API error, re-throw it.
      rethrow;
    }
  }

  // --------------------------------------------------------------------------
  // Core public request helper
  // --------------------------------------------------------------------------
  Future<http.Response> sendPublicRequest({
    required String method,
    required String path,
    JsonSerializable? body,
    bool requireAttestation = false,
  }) async {
    final url = Uri.parse('$baseUrl$path');
    // The helper now correctly handles all exceptions.
    return _executeRequestWithRetry(method, url, body, requireAttestation);
  }
}

