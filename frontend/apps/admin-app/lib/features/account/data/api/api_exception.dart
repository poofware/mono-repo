// NEW FILE

/// A custom exception to simulate structured API errors from the backend.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, String>? fieldErrors;
  final dynamic entity; // To carry the conflicting entity on 409

  ApiException(
    this.statusCode,
    this.message, [
    this.fieldErrors,
    this.entity,
  ]);

  @override
  String toString() {
    String output = 'ApiException: $statusCode - $message';
    if (fieldErrors != null && fieldErrors!.isNotEmpty) {
      output += '. Field Errors: $fieldErrors';
    }
    if (entity != null) {
      output += '. Entity: $entity';
    }
    return output;
  }
}