// NEW FILE
import 'package:poof_flutter_auth/poof_flutter_auth.dart';

class AdminLoginRequest implements JsonSerializable {
  final String username;
  final String password;
  final String totpCode;

  const AdminLoginRequest({
    required this.username,
    required this.password,
    required this.totpCode,
  });

  @override
  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        'totp_code': totpCode,
      };
}