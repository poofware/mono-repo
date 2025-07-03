import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart'
    show SessionManager, JsonSerializable;
import 'package:poof_pm/core/providers/app_state_provider.dart';

import 'package:poof_pm/features/auth/providers/pm_auth_providers.dart';

/// A PM-specific AuthController that coordinates login, logout, etc.
/// In a real setup, you'll inject a [PmAuthRepository].
/// We wire up the [SessionManager] from `flutter_auth` to handle the
/// token lifecycle (login, logout, refresh).
class AuthController {
  final Ref _ref;
  late final SessionManager _sessionManager;

  AuthController(this._ref) {
    final repo = _ref.read(pmAuthRepositoryProvider);

    _sessionManager = SessionManager(
      repo,
      onLoginStateChanged: (loggedIn) =>
          _ref.read(appStateProvider.notifier).setLoggedIn(loggedIn),
    );
  }

  /// Called at app startup to restore or refresh tokens (if any).
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

