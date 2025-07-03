// lib/src/utils/request_utils.dart
//
// UPDATED: Now correctly catches `http.ClientException` alongside `SocketException`
// to handle transient network errors like "Connection closed before full header was received".

import 'dart:async';
import 'dart:io' show SocketException, HttpException; // ClientException is NOT in dart:io
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http; // http.ClientException is here
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;

// Platform-specific client factory
import 'http_client_io.dart'
    if (dart.library.html) 'http_client_web.dart' as platform_client;

/// Global 12-second timeout
const _kT = Duration(seconds: 12);
const _retryDelay = Duration(milliseconds: 750);

/// A wrapper around http calls that includes a single, silent retry for transient network errors.
Future<http.Response> doHttp(
  String method,
  Uri url,
  Map<String, String> headers,
  String? encodedBody,
) async {
  
  // This inner function performs the actual HTTP request once.
  Future<http.Response> makeRequest() async {
    final client = platform_client.createHttpClient();
    try {
      switch (method.toUpperCase()) {
        case 'GET':
          return await client.get(url, headers: headers).timeout(_kT);
        case 'POST':
          return await client.post(url, headers: headers, body: encodedBody).timeout(_kT);
        case 'PUT':
          return await client.put(url, headers: headers, body: encodedBody).timeout(_kT);
        case 'DELETE':
          return await client.delete(url, headers: headers, body: encodedBody).timeout(_kT);
        case 'PATCH':
          return await client.patch(url, headers: headers, body: encodedBody).timeout(_kT);
        default:
          throw ApiException('Unsupported HTTP method: $method');
      }
    } finally {
      client.close(); // no-op on web
    }
  }

  try {
    return await makeRequest();
  // UPDATED: Catching http.ClientException and SocketException as they both represent
  // retryable, low-level network failures.
  } on http.ClientException catch (e) {
    debugPrint('[doHttp] Caught ClientException: "${e.message}". Retrying request to $url in $_retryDelay...');
    await Future.delayed(_retryDelay);
    try {
      return await makeRequest();
    } catch (retryErr) {
      debugPrint('[doHttp] Retry failed for $url. Error: $retryErr');
      throw ApiException('A network error occurred', errorCode: 'network_error', cause: retryErr);
    }
  } on SocketException catch (e) {
    debugPrint('[doHttp] Caught SocketException: "${e.message}". Retrying request to $url in $_retryDelay...');
    await Future.delayed(_retryDelay);
    try {
      return await makeRequest();
    } catch (retryErr) {
      debugPrint('[doHttp] Retry failed for $url. Error: $retryErr');
      throw ApiException('No internet connection', errorCode: 'network_offline', cause: retryErr);
    }
  } on HttpException catch (e) {
    debugPrint('[doHttp] Caught HttpException: "${e.message}". Retrying request to $url in $_retryDelay...');
    await Future.delayed(_retryDelay);
    try {
      return await makeRequest();
    } catch (retryErr) {
      debugPrint('[doHttp] Retry failed for $url. Error: $retryErr');
      throw ApiException('A network error occurred', errorCode: 'network_error', cause: retryErr);
    }
  } on TimeoutException catch (e) {
    debugPrint('[doHttp] Request to $url timed out.');
    throw ApiException('Request timed out', errorCode: 'network_timeout', cause: e);
  }
}
