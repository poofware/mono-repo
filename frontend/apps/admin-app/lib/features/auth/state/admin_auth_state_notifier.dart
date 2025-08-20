// NEW FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_auth_state.dart';

class AdminAuthStateNotifier extends StateNotifier<AdminAuthState> {
  AdminAuthStateNotifier() : super(const AdminAuthState());

  void setCredentials(String username, String password) {
    state = state.copyWith(username: username, password: password);
  }

  void clearCredentials() {
    state = const AdminAuthState();
  }
}