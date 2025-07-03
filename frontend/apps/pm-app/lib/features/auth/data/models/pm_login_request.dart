import 'package:poof_flutter_auth/poof_flutter_auth.dart' show JsonSerializable;

/// Mirrors the backend’s `LoginPMRequest`.
/// For TOTP-based login, we pass `email` + `totp_code`.
class PmLoginRequest implements JsonSerializable {
  final String email;
  final String totpCode;

  const PmLoginRequest({
    required this.email,
    required this.totpCode,
  });

  @override
  Map<String, dynamic> toJson() => {
        'email': email,
        'totp_code': totpCode,
      };
}

