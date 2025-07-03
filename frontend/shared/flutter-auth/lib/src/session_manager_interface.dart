// lib/src/session_manager_interface.dart

import 'models/models.dart';

/// Defines a common contract for session management across platforms.
/// This allows a controller to use either a web-specific (cookie-based)
/// or mobile-specific (token-storage-based) session manager interchangeably.
abstract class SessionManagerInterface {
  /// Initializes the session at app startup.
  /// For mobile, this may involve checking for stored tokens and refreshing them.
  /// For web, this typically involves a silent refresh call to check for a valid session cookie.
  Future<void> init();

  /// Performs a sign-in operation with the given credentials.
  /// On success, it should update the application's login state.
  Future<void> signIn<TLoginRequest extends JsonSerializable>(
      TLoginRequest credentials);

  /// Performs a sign-out operation.
  /// This should clear the session on the server and update the local login state.
  Future<void> signOut();

  /// Handles an authentication loss event, such as a failed token refresh mid-session.
  /// This forces a sign-out state locally.
  Future<void> handleAuthLost();

  /// A synchronous way to check the current login state held by the manager.
  bool get isLoggedIn;
}