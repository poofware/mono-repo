import 'package:poof_flutter_auth/poof_flutter_auth.dart' show JsonSerializable;

/// Mirrors the backend’s `RegisterPMRequest`.
/// We collect everything from the sign-up flow: name, email, phone, business name,
/// business address, city, state, zip, plus TOTP secret/token.
class PmRegisterRequest implements JsonSerializable {
  final String firstName;
  final String lastName;
  final String email;
  final String? phoneNumber; // phone is optional for PM
  final String businessName;
  final String businessAddress;
  final String city;
  final String state;
  final String zipCode;
  final String totpSecret;
  final String totpToken;

  const PmRegisterRequest({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.businessName,
    required this.businessAddress,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.totpSecret,
    required this.totpToken,
    this.phoneNumber, // optional
  });

  @override
  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'phone_number': phoneNumber,
        'business_name': businessName,
        'business_address': businessAddress,
        'city': city,
        'state': state,
        'zip_code': zipCode,
        'totp_secret': totpSecret,
        'totp_token': totpToken,
      };
}

