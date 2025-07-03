class SignUpState {
  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber;

  // If you want to store address or aptSuite, city, etc.:
  final String streetAddress;
  final String aptSuite;
  final String city;
  final String stateName; // "state" might conflict in Dart
  final String zipCode;

  // Vehicle
  final int vehicleYear;
  final String vehicleMake;
  final String vehicleModel;

  // TOTP secret we got from the server
  final String totpSecret;

  const SignUpState({
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.phoneNumber = '',
    this.streetAddress = '',
    this.aptSuite = '',
    this.city = '',
    this.stateName = '',
    this.zipCode = '',
    this.vehicleYear = 0,
    this.vehicleMake = '',
    this.vehicleModel = '',
    this.totpSecret = '',
  });

  SignUpState copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? phoneNumber,
    String? streetAddress,
    String? aptSuite,
    String? city,
    String? stateName,
    String? zipCode,
    int? vehicleYear,
    String? vehicleMake,
    String? vehicleModel,
    String? totpSecret,
  }) {
    return SignUpState(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      streetAddress: streetAddress ?? this.streetAddress,
      aptSuite: aptSuite ?? this.aptSuite,
      city: city ?? this.city,
      stateName: stateName ?? this.stateName,
      zipCode: zipCode ?? this.zipCode,
      vehicleYear: vehicleYear ?? this.vehicleYear,
      vehicleMake: vehicleMake ?? this.vehicleMake,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      totpSecret: totpSecret ?? this.totpSecret,
    );
  }
}

