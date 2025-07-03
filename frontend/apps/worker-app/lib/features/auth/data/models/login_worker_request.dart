import 'package:poof_flutter_auth/poof_flutter_auth.dart'
    show JsonSerializable;

class LoginWorkerRequest implements JsonSerializable {
  final String phoneNumber;
  final String totpCode;

  const LoginWorkerRequest({
    required this.phoneNumber,
    required this.totpCode,
  });

  @override
  Map<String, dynamic> toJson() => {
        'phone_number': phoneNumber,
        'totp_code': totpCode,
      };
}

