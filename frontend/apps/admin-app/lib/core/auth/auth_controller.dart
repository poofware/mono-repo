// NEW FILE
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/core/providers/app_state_provider.dart';
import 'package:poof_admin/features/auth/providers/admin_auth_providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';

/// An Admin-specific AuthController that coordinates login, logout, etc.
/// It uses a platform-specific session manager:
/// - `WebSessionManager` for web, which relies on HttpOnly cookies.
class AuthController {
  final Ref _ref;
  late final SessionManagerInterface _sessionManager;

  AuthController(this._ref) {
    final repo = _ref.read(adminAuthRepositoryProvider);

    if (kIsWeb) {
      _sessionManager = WebSessionManager(
        repo,
        onLoginStateChanged: (loggedIn) =>
            _ref.read(appStateProvider.notifier).setLoggedIn(loggedIn),
      );
    } else {
      // Mobile is not a target for the admin app, but for completeness:
      _sessionManager = SessionManager(
        repo,
        onLoginStateChanged: (loggedIn) =>
            _ref.read(appStateProvider.notifier).setLoggedIn(loggedIn),
      );
    }
  }

  /// Called at app startup to restore or refresh the session.
  Future<void> initSession() async {
    await _sessionManager.init();
  }

  /// Performs the login API call.
  Future<void> signIn<T extends JsonSerializable>(T creds) async {
    await _sessionManager.signIn(creds);
  }

  /// Performs the logout API call.
  Future<void> signOut() async {
    await _sessionManager.signOut();
  }

  /// Handles an authentication loss event (e.g., a failed API call).
  Future<void> handleAuthLost() async {
    await _sessionManager.handleAuthLost();
  }
}