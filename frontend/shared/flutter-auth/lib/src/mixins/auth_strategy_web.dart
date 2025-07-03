// flutter-auth/lib/src/mixins/auth_strategy_web.dart

import 'dart:async'; // NEW: Import for Completer
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../exceptions/api_exceptions.dart';
import '../models/models.dart';
import '../utils/header_utils.dart';
import '../utils/request_utils.dart';
import 'auth_strategy.dart';

class WebAuthStrategy extends AuthStrategy {
  final String baseUrl;
  final String authBaseUrl;
  final String refreshTokenPath;
  final void Function()? _onAuthLost;

  /// NEW: Whether we do real attestation or dummy on mobile.
  /// On web, it effectively won't matter, but let's store it.
  final bool isRealAttestation;

  // NEW: A completer to act as a lock for the refresh operation.
  Completer<bool>? _refreshCompleter;

  WebAuthStrategy({
    required this.baseUrl,
    required this.authBaseUrl,
    required this.refreshTokenPath,
    void Function()? onAuthLost,
    this.isRealAttestation = false,
  }) : _onAuthLost = onAuthLost;

  @override
  Future<http.Response> sendAuthenticatedRequest({
    required String method,
    required String path,
    JsonSerializable? body,
    bool attemptRefreshOn401 = true,
    bool requireAttestation = false,
  }) async {
    http.Response resp = await _do(
      method: method,
      path: path,
      body: body,
      requireAttestation: requireAttestation,
    );

    if (resp.statusCode == 401 && attemptRefreshOn401) {
      final refreshed = await performTokenRefresh();
      if (!refreshed) {
        throw ApiException('Cookie refresh failed', errorCode: 'refresh_failed');
      }
      resp = await _do(
        method: method,
        path: path,
        body: body,
        requireAttestation: requireAttestation,
      );
    }

    if (resp.statusCode >= 400) {
      throw ApiException.fromHttpResponse(resp.statusCode, resp.body);
    }
    return resp;
  }

  @override
  Future<bool> performTokenRefresh() async {
    // If a refresh is already in progress, wait for it to complete.
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    // Lock: create a new completer.
    _refreshCompleter = Completer<bool>();

    try {
      final success = await _executeRefresh();
      // Complete the future with the result.
      _refreshCompleter!.complete(success);
      return success;
    } catch (e) {
      // If an error occurs, complete the future with an error.
      _refreshCompleter!.completeError(e);
      rethrow;
    } finally {
      // Unlock: reset the completer for the next refresh cycle.
      _refreshCompleter = null;
    }
  }

  /// The actual token refresh logic, extracted to be used by the locking mechanism.
  Future<bool> _executeRefresh() async {
    final url = Uri.parse('$authBaseUrl$refreshTokenPath');
    final headers = <String, String>{'Content-Type': 'application/json'};
    injectWebHeaders(headers: headers, url: url);

    final resp = await doHttp('POST', url, headers, null);
    if (resp.statusCode >= 400) {
      _onAuthLost?.call();
      return false;
    }
    return true;
  }

  Future<http.Response> _do({
    required String method,
    required String path,
    JsonSerializable? body,
    bool requireAttestation = false,
  }) async {
    final url = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    injectWebHeaders(headers: headers, url: url);

    final encoded = body == null ? null : jsonEncode(body.toJson());
    return doHttp(method, url, headers, encoded);
  }
  
  // You haven't implemented multipart for web, which is fine.
  // We'll leave the default unimplemented error.
}
