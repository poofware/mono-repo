import 'package:poof_flutter_auth/poof_flutter_auth.dart'
    show JsonSerializable;

/// Typed request model for worker registration,
/// mirroring Go's RegisterWorkerRequest
class RegisterWorkerRequest implements JsonSerializable {
  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber;
  final String totpSecret;
  final String totpToken;

  const RegisterWorkerRequest({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneNumber,
    required this.totpSecret,
    required this.totpToken,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone_number': phoneNumber,
      'totp_secret': totpSecret,
      'totp_token': totpToken,
    };
  }
}

