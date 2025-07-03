import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pm_sign_up_state.dart';

/// Holds the partial sign-up data across multiple pages,
/// allowing the final TOTP step to call doRegister with everything.
class PmSignUpStateNotifier extends StateNotifier<PmSignUpState> {
  PmSignUpStateNotifier() : super(const PmSignUpState());

  void setBasicInfo({
    required String firstName,
    required String lastName,
    required String email,
    required String phoneNumber,
    required String companyName,
  }) {
    state = state.copyWith(
      firstName:   firstName,
      lastName:    lastName,
      email:       email,
      phoneNumber: phoneNumber, // can be empty if user omitted
      companyName: companyName,
    );
  }

  void setCompanyAddress({
    required String street,
    required String city,
    required String stateName,
    required String zip,
  }) {
    state = state.copyWith(
      companyStreet: street,
      companyCity:   city,
      companyState:  stateName,
      companyZip:    zip,
    );
  }

  void setTotpSecret(String secret) {
    state = state.copyWith(totpSecret: secret);
  }

  void clearAll() {
    state = const PmSignUpState();
  }
}

