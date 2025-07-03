import 'package:http/http.dart' as http;
import '../models/models.dart';

/// The core interface that any authentication strategy (mobile/desktop vs web)
/// must implement.
abstract class AuthStrategy {
  /// Sends an authenticated JSON request (bearer token), optionally attempts a
  /// refresh on 401, then returns the final response or throws an ApiException.
  Future<http.Response> sendAuthenticatedRequest({
    required String method,
    required String path,
    JsonSerializable? body,
    bool attemptRefreshOn401,
    // No device attestation by default, but you can request it
    bool requireAttestation = false,
  });

  /// Attempts to refresh the current token pair (access + refresh). Returns true
  /// if successful, or false if refresh fails. Also allows requesting device
  /// attestation for the refresh call if needed.
  Future<bool> performTokenRefresh();

  /// A dedicated function to handle multipart requests with the same
  /// 401→refresh→retry logic as [sendAuthenticatedRequest].
  Future<http.Response> sendAuthenticatedMultipartRequest({
    String method = 'POST',
    required String path,
    Map<String, String>? fields,
    List<Object>? files,
    bool attemptRefreshOn401 = true,
    bool requireAttestation = false,
  }) {
    return Future.error(
      UnimplementedError(
        'sendAuthenticatedMultipartRequest() is not implemented for '
        '${runtimeType}. '
        'Either override it in your AuthStrategy subclass or avoid calling '
        'multipart endpoints on this platform.',
      ),
      StackTrace.current,
    );
  }
}

