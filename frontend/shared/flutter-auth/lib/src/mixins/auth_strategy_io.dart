// flutter-auth/lib/src/mixins/auth_strategy_io.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../exceptions/api_exceptions.dart';
import '../models/models.dart';
import '../token_storage.dart';
import '../utils/attestation_helper.dart';
import '../utils/device_attestation_utils.dart' as attestation;
import '../utils/header_utils.dart';
import '../utils/request_utils.dart';
import 'auth_strategy.dart';

/// A robust, mobile-first authentication strategy for managing tokens and device attestation.
///
/// This class orchestrates:
///   - Attaching bearer tokens to outgoing requests.
///   - Automatically refreshing expired tokens upon receiving a 401 response.
///   - Automatically performing iOS re-attestation if the backend loses the public key.
///   - Thread-safe token refreshing to prevent race conditions.
class IoAuthStrategy implements AuthStrategy {
  final String baseUrl;
  final String refreshTokenBaseUrl;
  final String refreshTokenPath;
  final BaseTokenStorage _tokenStorage;
  final void Function()? _onAuthLost;
  final bool isRealAttestation;

  late final AttestationHelper _attestationHelper;
  static Completer<bool>? _refreshCompleter;

  IoAuthStrategy({
    required this.baseUrl,
    required this.refreshTokenBaseUrl,
    required this.refreshTokenPath,
    required BaseTokenStorage tokenStorage,
    void Function()? onAuthLost,
    this.isRealAttestation = false,
    required String attestationChallengeBaseUrl,
    required String attestationChallengePath,
  })  : _tokenStorage = tokenStorage,
        _onAuthLost = onAuthLost {
    _attestationHelper = AttestationHelper(
      challengeBaseUrl: attestationChallengeBaseUrl,
      challengePath: attestationChallengePath,
      useRealAttestation: isRealAttestation,
    );
  }

  // --- PUBLIC API ---

  @override
  Future<http.Response> sendAuthenticatedRequest({
    required String method,
    required String path,
    JsonSerializable? body,
    bool attemptRefreshOn401 = true,
    bool requireAttestation = false,
  }) {
    // This is the "request-making" closure that the core handler will execute.
    // It knows how to build and send a standard JSON request.
    final requestMaker = (String accessToken) async {
      final url = Uri.parse('$baseUrl$path');
      final headers =
          await _buildHeaders(accessToken, requireAttestation: requireAttestation);
      final encodedBody = body == null ? null : jsonEncode(body.toJson());

      return doHttp(method, url, headers, encodedBody);
    };

    return _executeRequest(requestMaker, attemptRefreshOn401: attemptRefreshOn401);
  }

  @override
  Future<http.Response> sendAuthenticatedMultipartRequest({
    String method = 'POST',
    required String path,
    Map<String, String>? fields,
    List<Object>? files,
    bool attemptRefreshOn401 = true,
    bool requireAttestation = false,
  }) {
    // The closure for making a multipart request.
    final requestMaker = (String accessToken) async {
      final uri = Uri.parse('$baseUrl$path');
      final request = http.MultipartRequest(method, uri);

      request.headers.addAll(
          await _buildHeaders(accessToken, requireAttestation: requireAttestation));
      fields?.forEach((k, v) => request.fields[k] = v);

      if (files != null && files.isNotEmpty) {
        for (final f in files) {
          if (f is File) {
            final length = await f.length();
            final stream = http.ByteStream(f.openRead());
            final filename = f.path.split('/').last;
            request.files.add(
              http.MultipartFile('photo', stream, length, filename: filename),
            );
          }
        }
      }

      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    };

    return _executeRequest(requestMaker, attemptRefreshOn401: attemptRefreshOn401);
  }

  @override
  Future<bool> performTokenRefresh() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<bool>();

    try {
      final ok = await _executeRefresh();
      _refreshCompleter!.complete(ok);
      return ok;
    } catch (e) {
      _refreshCompleter!.completeError(e);
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  // --- CORE LOGIC ---

  /// The main request orchestrator. Handles token retrieval, execution,
  /// and the refresh-then-retry flow. It's wrapped by re-attestation logic.
  Future<http.Response> _executeRequest(
    Future<http.Response> Function(String accessToken) requestMaker, {
    required bool attemptRefreshOn401,
  }) async {
    // This outer function is the "decorator" that handles re-attestation.
    return _withReattestationRetry(() async {
      final tokens = await _tokenStorage.getTokens();
      if (tokens == null) {
        throw ApiException('No tokens available', errorCode: 'no_tokens');
      }

      var response = await requestMaker(tokens.accessToken);

      // If we get a 401 and are allowed to refresh, try it.
      if (response.statusCode == 401 && attemptRefreshOn401) {
        final refreshed = await performTokenRefresh();
        if (!refreshed) {
          throw ApiException('Failed to refresh tokens',
              errorCode: 'refresh_failed');
        }

        final newTokens = await _tokenStorage.getTokens();
        if (newTokens == null) {
          throw ApiException('No new access token after refresh',
              errorCode: 'no_new_token');
        }

        // Retry the original request with the new token.
        response = await requestMaker(newTokens.accessToken);
      }

      // After all retries, if the status is still bad, throw.
      if (response.statusCode >= 400) {
        throw ApiException.fromHttpResponse(response.statusCode, response.body);
      }

      return response;
    });
  }

  /// The private refresh logic, also wrapped in re-attestation retry logic.
  Future<bool> _executeRefresh() async {
    return _withReattestationRetry(() async {
      final current = await _tokenStorage.getTokens();
      if (current == null) return false;

      final url = Uri.parse('$refreshTokenBaseUrl$refreshTokenPath');
      // Refresh is always attested
      final headers =
          await _buildHeaders(current.accessToken, requireAttestation: true);
      final body = jsonEncode({'refresh_token': current.refreshToken});

      final resp = await doHttp('POST', url, headers, body);

      if (resp.statusCode >= 400) {
        // If the refresh call itself fails, the session is truly lost.
        await _tokenStorage.clearTokens();
        _onAuthLost?.call();
        // We throw here so the original caller knows the refresh failed.
        throw ApiException.fromHttpResponse(resp.statusCode, resp.body);
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final access = decoded['access_token'] as String?;
      final refresh = decoded['refresh_token'] as String?;
      if (access == null || refresh == null) {
        await _tokenStorage.clearTokens();
        _onAuthLost?.call();
        return false;
      }

      await _tokenStorage
          .saveTokens(TokenPair(accessToken: access, refreshToken: refresh));
      return true;
    });
  }

  // --- HELPERS ---

  /// A decorator function that wraps a request-making function with re-attestation logic.
  Future<T> _withReattestationRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiException catch (e) {
      if (e.errorCode == 'key_not_found_for_assertion') {
        await attestation.clearIosKeyId();
        // After clearing the key, re-run the original action.
        // Its next call to `_buildHeaders` will trigger a full attestation.
        return await action();
      }

      // For any other error, let it bubble up. [cite: 34]
      rethrow;
    } on PlatformException catch (e) {
      // This will catch the underlying native error from App Attest.
      // We wrap it in a standard ApiException to be handled gracefully upstream.
      throw ApiException('Device attestation failed: ${e.message}',
          cause: e, errorCode: e.code);
    }
  }

  /// Builds the required headers for an authenticated request.
  Future<Map<String, String>> _buildHeaders(String accessToken,
      {required bool requireAttestation}) async {
    final headers = <String, String>{
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    };
    await injectMobileHeaders(headers: headers, includeDeviceId: true);

    if (requireAttestation) {
      final attestationHeaders =
          await _attestationHelper.getAttestationHeaders();
      headers.addAll(attestationHeaders);
    }
    return headers;
  }
}
