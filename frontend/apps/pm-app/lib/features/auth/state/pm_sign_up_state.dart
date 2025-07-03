/// Holds the partial sign-up data while the user moves through
/// the multi-step flow: create account → company address → email verify → TOTP.
class PmSignUpState {
  // Basic info
  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber; // optional, can be empty

  // Company/business info
  final String companyName;       // business_name
  final String companyStreet;     // business_address
  final String companyCity;
  final String companyState;
  final String companyZip;

  // TOTP data
  final String totpSecret; // from server
  // We do not store the totpToken here since it's ephemeral

  const PmSignUpState({
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.phoneNumber = '',
    this.companyName = '',
    this.companyStreet = '',
    this.companyCity = '',
    this.companyState = '',
    this.companyZip = '',
    this.totpSecret = '',
  });

  PmSignUpState copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? phoneNumber,
    String? companyName,
    String? companyStreet,
    String? companyCity,
    String? companyState,
    String? companyZip,
    String? totpSecret,
  }) {
    return PmSignUpState(
      firstName:      firstName      ?? this.firstName,
      lastName:       lastName       ?? this.lastName,
      email:          email          ?? this.email,
      phoneNumber:    phoneNumber    ?? this.phoneNumber,
      companyName:    companyName    ?? this.companyName,
      companyStreet:  companyStreet  ?? this.companyStreet,
      companyCity:    companyCity    ?? this.companyCity,
      companyState:   companyState   ?? this.companyState,
      companyZip:     companyZip     ?? this.companyZip,
      totpSecret:     totpSecret     ?? this.totpSecret,
    );
  }
}

