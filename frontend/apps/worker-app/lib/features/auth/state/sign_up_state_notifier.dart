import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sign_up_state.dart';

class SignUpStateNotifier extends StateNotifier<SignUpState> {
  SignUpStateNotifier() : super(const SignUpState());

  void setBasicInfo({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneNumber,
  }) {
    state = state.copyWith(
      firstName: firstName,
      lastName: lastName,
      email: email,
      phoneNumber: phoneNumber,
    );
  }

  void setAddressInfo({
    required String streetAddress,
    required String aptSuite,
    required String city,
    required String stateName,
    required String zipCode,
  }) {
    state = state.copyWith(
      streetAddress: streetAddress,
      aptSuite: aptSuite,
      city: city,
      stateName: stateName,
      zipCode: zipCode,
    );
  }

  void setVehicleInfo({
    int? vehicleYear,
    String? vehicleMake,
    String? vehicleModel,
  }) {
    state = state.copyWith(
      vehicleYear: vehicleYear,
      vehicleMake: vehicleMake,
      vehicleModel: vehicleModel,
    );
  }

  void setTotpSecret(String secret) {
    state = state.copyWith(totpSecret: secret);
  }
}
