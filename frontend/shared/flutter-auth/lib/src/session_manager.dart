// lib/poof_flutter_auth/src/session/session_manager.dart

import 'base_auth_repository.dart';
import 'models/models.dart';
import 'session_manager_interface.dart';

/// A pure-Dart class managing session lifecycle (silent refresh, logout).
/// Consumers wire the [onLoginStateChanged] callback into their preferred
/// state-management approach (Riverpod, Bloc, etc.).
class SessionManager implements SessionManagerInterface {
  final BaseAuthRepository _repo;
  final void Function(bool loggedIn) onLoginStateChanged;

  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;

  SessionManager(
    this._repo, {
    required this.onLoginStateChanged,
  });

  /// Called once at app startup. If we have tokens, tries a silent refresh.
  /// If refresh fails, sets isLoggedIn = false.
  Future<void> init() async {
    final hasTokens = await _repo.hasTokens();
    if (!hasTokens) {
      _setLoggedIn(false);
      return;
    }

    final refreshed = await _repo
        .doRefreshToken()
        .then((_) => true)
        .catchError((_) => false);
    _setLoggedIn(refreshed);
  }

  /// Performs the concrete repository login and, on success,
  /// marks the app as logged‑in so the router guards pass.
  Future<void> signIn<TLoginRequest extends JsonSerializable>(
      TLoginRequest credentials) async {
    await _repo.doLogin(credentials);   // now type‑safe
    _setLoggedIn(true);
  }

  /// Sign-out explicitly (user-initiated).
  Future<void> signOut() async {
    await _repo.doLogout();
    _setLoggedIn(false);
  }

  /// Called by the API layer when refresh fails mid-session.
  Future<void> handleAuthLost() async {
    await _repo.tokenStorage.clearTokens();
    _setLoggedIn(false);
  }

  void _setLoggedIn(bool v) {
    if (_isLoggedIn == v) return; // no change
    _isLoggedIn = v;
    onLoginStateChanged(v);
  }

  // ───────────────────────────────────────────────────────────
  //  Called when the device comes back online.  If the user is
  //  currently logged-out *but* we still have tokens, attempt a
  //  silent refresh once.
  // ───────────────────────────────────────────────────────────
  Future<void> tryReconnect() async {
    if (_isLoggedIn) return;                 // already signed-in
    final hasTokens = await _repo.hasTokens();
    if (!hasTokens) return;                  // nothing to refresh

    final refreshed = await _repo
        .doRefreshToken()                    // may throw
        .then((_) => true)
        .catchError((_) => false);

    _setLoggedIn(refreshed);                 // triggers router redirect
  }
}

