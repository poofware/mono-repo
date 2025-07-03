import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_pm/core/auth/auth_controller.dart';

/// Provides a single AuthController instance, giving centralized
/// access to sign-in, sign-out, refresh, etc.
final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController(ref);
});

