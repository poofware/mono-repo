// ./src/api_exceptions.dart

import 'dart:convert';

/// A standard error response shape from your Go backend:
/// {
///   "code":    "<short_code>",
///   "message": "<user_friendly_message>"
/// }
class PoofErrorResponse {
  final String code;
  final String message;

  PoofErrorResponse({required this.code, required this.message});

  factory PoofErrorResponse.fromJson(Map<String, dynamic> json) {
    return PoofErrorResponse(
      code: json['code'] as String,
      message: json['message'] as String,
    );
  }
}

/// Base exception class for Poof auth & API calls.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? errorCode; // Additional field to store "code" from server
  final dynamic cause;

  ApiException(
    this.message, {
    this.statusCode,
    this.errorCode,
    this.cause,
  });

  @override
  String toString() {
    // Start by describing *this* exception
    final sb = StringBuffer('ApiException');
    if (statusCode != null) {
      sb.write('($statusCode)');
    }
    if (errorCode != null) {
      sb.write('[$errorCode]');
    }
    sb.write(': $message');

    // If there’s a cause, recursively format it
    if (cause != null) {
      sb.write(_formatCause(cause, indentLevel: 1));
    }

    return sb.toString();
  }

  String _formatCause(dynamic cause, {int indentLevel = 1}) {
    // Build an indentation prefix
    final indent = '  ' * indentLevel;

    // If it's another ApiException, we recursively call toString() on it
    if (cause is ApiException) {
      // Indent, then append cause's own toString()
      return '\n${indent}Caused by -> ${cause.toString().replaceAll('\n', '\n$indent')}';
    }

    // If it's some other type of error/exception, we just attach its .toString()
    return '\n${indent}Caused by -> $cause';
  }

  /// Attempts to parse an error response from the HTTP [body].
  /// If parsing fails, returns a generic ApiException.
  static ApiException fromHttpResponse(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final err = PoofErrorResponse.fromJson(decoded);
      return ApiException(
        err.message,
        statusCode: statusCode,
        errorCode: err.code,
      );
    } catch (_) {
      // If the body is not valid JSON or doesn't match shape,
      // fallback to a generic message.
      return ApiException(
        'Request failed with status $statusCode: $body',
        statusCode: statusCode,
      );
    }
  }
}
