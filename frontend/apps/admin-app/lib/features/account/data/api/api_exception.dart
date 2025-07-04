// NEW FILE

/// A custom exception to simulate structured API errors from the backend.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, String>? fieldErrors;

  ApiException(
    this.statusCode,
    this.message, [
    this.fieldErrors,
  ]);

  @override
  String toString() {
    if (fieldErrors != null && fieldErrors!.isNotEmpty) {
      return 'ApiException: $statusCode - $message. Field Errors: $fieldErrors';
    }
    return 'ApiException: $statusCode - $message';
  }
}