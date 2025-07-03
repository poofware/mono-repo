// ./src/token_storage.dart

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models/models.dart';

/// A base class for storing & retrieving tokens locally.
abstract class BaseTokenStorage {
  Future<void> saveTokens(TokenPair tokens);
  Future<TokenPair?> getTokens();
  Future<void> clearTokens();
}

/// A Flutter Secure Storage-based implementation for storing tokens.
/// You can specify different key names if you want to differentiate
/// between Worker vs PM by passing them in the constructor.
class SecureTokenStorage implements BaseTokenStorage {
  final _storage = const FlutterSecureStorage();

  final String accessTokenKey;
  final String refreshTokenKey;

  SecureTokenStorage({
    this.accessTokenKey = 'poof_access_token',
    this.refreshTokenKey = 'poof_refresh_token',
  });

  @override
  Future<void> saveTokens(TokenPair tokens) async {
    await _storage.write(key: accessTokenKey, value: tokens.accessToken);
    await _storage.write(key: refreshTokenKey, value: tokens.refreshToken);
  }

  @override
  Future<TokenPair?> getTokens() async {
    final access = await _storage.read(key: accessTokenKey);
    final refresh = await _storage.read(key: refreshTokenKey);
    if (access == null || refresh == null) {
      return null;
    }
    return TokenPair(
      accessToken: access,
      refreshToken: refresh,
    );
  }

  @override
  Future<void> clearTokens() async {
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
  }
}

/// A no-operation token storage implementation.
/// 
/// Useful for web scenarios where tokens are stored securely in HTTP-only cookies,
/// and you explicitly want to ensure tokens never touch client-side storage.
class NoOpTokenStorage implements BaseTokenStorage {
  @override
  Future<void> saveTokens(TokenPair tokens) async {
    // Intentionally do nothing.
  }

  @override
  Future<TokenPair?> getTokens() async {
    // Tokens are managed via cookies; always return null explicitly.
    return null;
  }

  @override
  Future<void> clearTokens() async {
    // Intentionally do nothing.
  }
}

