// NEW FILE
class Admin {
  final String id;
  final String username;
  final String accountStatus;
  final String setupProgress;

  Admin({
    required this.id,
    required this.username,
    required this.accountStatus,
    required this.setupProgress,
  });

  factory Admin.fromJson(Map<String, dynamic> json) {
    return Admin(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      accountStatus: json['account_status'] as String? ?? 'UNKNOWN',
      setupProgress: json['setup_progress'] as String? ?? 'UNKNOWN',
    );
  }
}