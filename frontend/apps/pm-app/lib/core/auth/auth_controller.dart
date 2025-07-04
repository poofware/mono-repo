import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_pm/core/providers/app_state_provider.dart';

import 'package:poof_pm/features/auth/providers/pm_auth_providers.dart';

/// A PM-specific AuthController that coordinates login, logout, etc.
/// It uses a platform-specific session manager:
/// - `SessionManager` for mobile, which handles local token storage.
/// - `WebSessionManager` for web, which relies on HttpOnly cookies.
class AuthController {
  final Ref _ref;
  late final SessionManagerInterface _sessionManager;

  AuthController(this._ref) {
    final repo = _ref.read(pmAuthRepositoryProvider);

    if (kIsWeb) {
      // For web, use the cookie-based session manager.
      _sessionManager = WebSessionManager(
        repo,
        onLoginStateChanged: (loggedIn) =>
            _ref.read(appStateProvider.notifier).setLoggedIn(loggedIn),
      );
    } else {
      // For mobile (if ever used), use the standard token-storage-based session manager.
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

  /// Example sign-in method
  Future<void> signIn<T extends JsonSerializable>(T creds) async {
    await _sessionManager.signIn(creds);
  }

  /// Example sign-out method
  Future<void> signOut() async {
    await _sessionManager.signOut();
  }

  /// If refresh fails, forcibly log out
  Future<void> handleAuthLost() async {
    await _sessionManager.handleAuthLost();
  }
}