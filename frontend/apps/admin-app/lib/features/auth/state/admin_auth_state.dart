// NEW FILE
class AdminAuthState {
  final String username;
  final String password;

  const AdminAuthState({this.username = '', this.password = ''});

  AdminAuthState copyWith({
    String? username,
    String? password,
  }) {
    return AdminAuthState(
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }
}