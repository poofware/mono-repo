// NEW FILE
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_admin/features/auth/data/models/admin.dart';
import 'admin_user_state.dart';

class AdminUserStateNotifier extends StateNotifier<AdminUserState> {
  AdminUserStateNotifier() : super(const AdminUserState());

  Admin? get user => state.adminUser;

  void setAdminUser(Admin admin) {
    state = AdminUserState(adminUser: admin);
  }

  void clearAdminUser() {
    state = const AdminUserState(adminUser: null);
  }
}