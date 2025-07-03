// lib/src/web_session_manager.dart
import 'package:flutter/foundation.dart' show kIsWeb;

import 'base_auth_repository.dart';
import 'models/models.dart';
import 'session_manager_interface.dart';

/// A web-specific session manager that relies on the browser's handling of
/// secure, HttpOnly cookies for session management.
///
/// It does not interact with local token storage. Instead, its state is
/// determined by making API calls and letting the browser manage cookies.
class WebSessionManager implements SessionManagerInterface {
  final BaseAuthRepository _repo;
  final void Function(bool loggedIn) onLoginStateChanged;

  bool _isLoggedIn = false;
  @override
  bool get isLoggedIn => _isLoggedIn;

  WebSessionManager(
    this._repo, {
    required this.onLoginStateChanged,
  }) {
    // This manager should only be used on the web.
    assert(kIsWeb, 'WebSessionManager is intended for web use only.');
  }

  /// At app startup on the web, we don't check for local tokens.
  /// Instead, we directly attempt a silent refresh. If the browser has a valid
  /// HttpOnly session cookie, the refresh will succeed, and we'll be logged in.
  /// Otherwise, it will fail, and we'll be logged out.
  @override
  Future<void> init() async {
    final refreshed = await _repo
        .doRefreshToken()
        .then((_) => true)
        .catchError((_) => false);
    _setLoggedIn(refreshed);
  }

  /// Performs the login API call. The backend is expected to set HttpOnly
  /// cookies upon success. This manager simply updates the app's login state.
  @override
  Future<void> signIn<TLoginRequest extends JsonSerializable>(
      TLoginRequest credentials) async {
    await _repo.doLogin(credentials);
    _setLoggedIn(true);
  }

  /// Calls the logout endpoint, which should instruct the browser to clear
  /// the session cookies. This manager then updates the app's login state.
  @override
  Future<void> signOut() async {
    await _repo.doLogout();
    _setLoggedIn(false);
  }

  /// Handles an authentication loss event (e.g., a failed API call due to an
  /// expired session). There are no local tokens to clear, so we just update
  /// the app's login state to signed-out.
  @override
  Future<void> handleAuthLost() async {
    // For web, there are no local tokens to clear. The session is already lost.
    // We just need to update the UI state.
    _setLoggedIn(false);
  }

  void _setLoggedIn(bool value) {
    if (_isLoggedIn == value) return; // No change
    _isLoggedIn = value;
    onLoginStateChanged(value);
  }
}