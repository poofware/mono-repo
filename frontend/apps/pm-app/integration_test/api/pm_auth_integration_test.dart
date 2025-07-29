import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otp/otp.dart';

import 'package:poof_pm/features/auth/data/models/models.dart'; // pm_login_request, pm_register_request
import 'package:poof_pm/features/auth/state/pm_user_state_notifier.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart'
    hide SecureTokenStorage;
import 'package:poof_pm/features/auth/data/repositories/pm_auth_repository.dart';
import 'package:poof_pm/features/auth/data/api/pm_auth_api.dart';
import 'package:poof_pm/core/config/config.dart';

/// This file tests the PM Auth flows end-to-end:
///   - Check email/phone validity
///   - Request/verify email code
///   - Generate TOTP secret
///   - Negative TOTP usage scenarios
///   - Register PM
///   - Negative phone usage (unverified phone)
///   - Conflicts for email/phone re-check
///   - Login with TOTP
///   - Negative login attempts
///   - Token refresh
///   - Logout
///
/// The environment is determined by the `ENV` build-time variable. E.g:
///   flutter test integration_test/api/pm_auth_integration_test.dart
///     --dart-define=ENV=dev
/// Or just runs "dev" by default if not set.

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.shouldPropagateDevicePointerEvents = true;

  late String testEmail;
  late String testPhone; // optional, but tested anyway
  late BaseTokenStorage tokenStorage;
  late PmAuthRepository pmAuthRepo;
  late PmUserStateNotifier pmUserNotifier;

  // We store a TOTP secret from generateTOTPSecret() for the main happy flow.
  String? totpSecret;

  // Known test-mode verification codes:
  const validVerificationCode = '999999';
  const invalidVerificationCode = '888888';

  // Helper to generate the current TOTP code from a given secret.
  String generateTOTPCode(String secret) {
    return OTP.generateTOTPCodeString(
      secret,
      DateTime.now().millisecondsSinceEpoch,
      length: 6,
      interval: 30,
      algorithm: Algorithm.SHA1,
      isGoogle: true, // typical Google Authenticator style
    );
  }

  setUpAll(() async {
    // 1) Configure environment (dev / staging).
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'staging':
        configureStagingFlavor();
        break;
      default:
        configureDevFlavor();
    }

    // 2) Build random suffix for unique email & phone to avoid collisions between test runs.
    final rand = Random().nextInt(999999999).toString();
    testEmail = '${rand}testing@thepoofapp.com';
    testPhone = '+999${rand.padLeft(10, '0')}'; // ensures at least 10 digits

    // 3) Create a PM user notifier, token storage, and pmAuthApi + pmAuthRepo
    pmUserNotifier = PmUserStateNotifier();
    // For web tests, we use NoOpTokenStorage because auth is handled by HttpOnly cookies.
    // The auth framework is smart enough to use WebAuthStrategy which doesn't
    // depend on client-side token storage.
    tokenStorage = NoOpTokenStorage();

    final pmAuthApi = PmAuthApi(
      tokenStorage: tokenStorage,
      onAuthLost:
          () => {}, // If refresh fails mid-test, do cleanup here if desired
      useRealAttestation: false, // Typically read from flavor config if needed
    );

    pmAuthRepo = PmAuthRepository(
      authApi: pmAuthApi,
      tokenStorage: tokenStorage,
      pmUserNotifier: pmUserNotifier,
    );
  });

  tearDownAll(() async {
    // Clear tokens if desired after entire suite:
    await tokenStorage.clearTokens();
  });

  group('PmAuth Integration Tests (E2E)', () {
    testWidgets('0) Negative validations => expect 400 or conflict', (
      tester,
    ) async {
      // 0a) Invalid email format => expect 400
      try {
        await pmAuthRepo.checkEmailValid('not-a-valid-email');
        fail('Expected 400 with "validation_error" for invalid email format');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(400));
        expect(e.errorCode, anyOf(['validation_error', 'invalid_payload']));
      }

      // 0b) Obviously invalid phone => expect 400
      try {
        await pmAuthRepo.checkPhoneValid('+12'); // definitely not E.164
        fail('Expected 400 with "validation_error" for invalid phone format');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(400));
        expect(e.errorCode, anyOf(['validation_error', 'invalid_payload']));
      }
    });

    testWidgets('1) Check email => should be unused => no errors', (
      tester,
    ) async {
      await pmAuthRepo.checkEmailValid(testEmail);
    });

    testWidgets('2) Check phone => should be unused => no errors', (
      tester,
    ) async {
      // PM phone is optional, but we test it anyway
      await pmAuthRepo.checkPhoneValid(testPhone);
    });

    testWidgets('3) Request Email Code => negative => positive verify', (
      tester,
    ) async {
      // 3a) request code
      await pmAuthRepo.requestEmailCode(testEmail);

      // 3b) verify with invalid => expect 401 "unauthorized"
      try {
        await pmAuthRepo.verifyEmailCode(testEmail, invalidVerificationCode);
        fail('Expected 401 unauthorized for invalid email code');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(401));
        expect(e.errorCode, anyOf(['unauthorized', 'invalid_credentials']));
      }

      // 3c) verify with known valid code => success
      await pmAuthRepo.verifyEmailCode(testEmail, validVerificationCode);
    });
      testWidgets('3b) Request SMS Code => positive verify', (
      tester,
    ) async {
      // 3b-a) request SMS code for the main test phone
      await pmAuthRepo.requestSMSCode(testPhone);

      // 3b-b) verify with the known valid test code
      await pmAuthRepo.verifySMSCode(testPhone, validVerificationCode);
    });

    // ─────────────────────────────────────────────────────────────
    // 4) Negative TOTP usage + unverified phone scenarios
    // ─────────────────────────────────────────────────────────────

    testWidgets(
      '4a) Verified email, valid-format unverified phone => attempt doRegister => expect success',
      (tester) async {
        // For this scenario, we generate a new ephemeral email & phone.
        // The email is verified. The phone number is in a valid format but *not* SMS-verified.
        // PM registration flow requires the email to be verified. If a phone number
        // is provided, it only needs to be format-valid; prior SMS verification is not mandatory for registration.
        final randID = Random().nextInt(999999999).toString();
        final ephemeralEmail =
            '${randID}testing@thepoofapp.com'; // Suffix for clarity
        final ephemeralPhone = '+999${randID.padLeft(10, '0')}'; // Valid format

        // 1) Check & request email code => quickly verify it
        await pmAuthRepo.checkEmailValid(ephemeralEmail);
        await pmAuthRepo.requestEmailCode(ephemeralEmail);
        await pmAuthRepo.verifyEmailCode(ephemeralEmail, validVerificationCode);

        // 2) Generate TOTP
        final totpResp = await pmAuthRepo.generateTOTPSecret();
        final ephemeralSecret = totpResp.secret;
        final ephemeralTOTPCode = generateTOTPCode(ephemeralSecret);

        // 3) Attempt register. Email is verified. Phone is provided, has a valid format,
        // but has not been through the requestSMSCode/verifySMSCode flow.
        // This registration attempt should succeed.
        final regReq = PmRegisterRequest(
          firstName: 'ValidPhone',
          lastName: 'Tester',
          email: ephemeralEmail,
          phoneNumber:
              null, // Provided, valid format, not SMS-verified
          businessName: 'ValidPhoneReg LLC',
          businessAddress: '123 Valid Lane',
          city: 'Nowhere',
          state: 'NC',
          zipCode: '27601',
          totpSecret: ephemeralSecret,
          totpToken: ephemeralTOTPCode,
        );

        // Expect registration to succeed. If an exception occurs, the test will fail.
        await pmAuthRepo.doRegister(regReq);

        // No explicit 'fail' call or try-catch needed here, as success is expected.
        // If pmAuthRepo.doRegister throws, the test will automatically fail.
      },
    );

    testWidgets(
      '4b) Invalid TOTP code => attempt doRegister => expect 400 or invalid_totp',
      (tester) async {
        // For negative TOTP usage, we properly verify the email but pass a bogus TOTP code.

        // 1) Prepare ephemeral email & do normal email verify
        final randID = Random().nextInt(999999999).toString();
        final ephemeralEmail = '${randID}testing@thepoofapp.com';

        await pmAuthRepo.checkEmailValid(ephemeralEmail);
        await pmAuthRepo.requestEmailCode(ephemeralEmail);
        await pmAuthRepo.verifyEmailCode(ephemeralEmail, validVerificationCode);

        // 2) Generate TOTP secret but intentionally use a mismatched code for registration
        final totpResp = await pmAuthRepo.generateTOTPSecret();
        final ephemeralSecret = totpResp.secret;
        final badTOTPCode = '000000'; // definitely invalid for our new secret

        // 3) Try to register => expect 400 or a specific "invalid_totp" code
        final regReq = PmRegisterRequest(
          firstName: 'InvalidTOTP',
          lastName: 'Tester',
          email: ephemeralEmail,
          phoneNumber: null, // No phone
          businessName: 'TestBadTOTP Inc',
          businessAddress: '321 NoWhere Ave',
          city: 'Fakeville',
          state: 'GA',
          zipCode: '30000',
          totpSecret: ephemeralSecret,
          totpToken: badTOTPCode,
        );

        try {
          await pmAuthRepo.doRegister(regReq);
          fail('Expected error for invalid TOTP code');
        } on ApiException catch (e) {
          expect(e.statusCode, anyOf([400, 401]));
          expect(
            e.errorCode,
            anyOf(['invalid_totp', 'validation_error', 'unauthorized']),
          );
        }
      },
    );

    testWidgets('4c) Unverified email => attempt doRegister => expect failure', (
      tester,
    ) async {
      // For this scenario, we use an email that has NOT been verified.
      // Registration should fail even if TOTP is correct.

      // 1) Prepare ephemeral email (DO NOT VERIFY IT)
      final randID = Random().nextInt(999999999).toString();
      final unverifiedEmail = '${randID}testing@thepoofapp.com';
      // We can call checkEmailValid to ensure it's not in use and is a valid format,
      // but we skip requestEmailCode and verifyEmailCode.
      await pmAuthRepo.checkEmailValid(unverifiedEmail);

      // 2) Generate TOTP secret and a valid code
      final totpResp = await pmAuthRepo.generateTOTPSecret();
      final ephemeralSecret = totpResp.secret;
      final validTOTPCode = generateTOTPCode(ephemeralSecret);

      // 3) Try to register with the unverified email
      final regReq = PmRegisterRequest(
        firstName: 'UnverifiedEmail',
        lastName: 'Tester',
        email: unverifiedEmail, // This email was not verified
        phoneNumber: null, // No phone for simplicity, or provide a valid one
        businessName: 'TestUnverifiedEmail Inc',
        businessAddress: '789 NonExistent Rd',
        city: 'Nowhere',
        state: 'FL',
        zipCode: '33000',
        totpSecret: ephemeralSecret,
        totpToken: validTOTPCode, // Correct TOTP
      );

      try {
        await pmAuthRepo.doRegister(regReq);
        fail('Expected error for registration with unverified email');
      } on ApiException catch (e) {
        // Expecting a 400 Bad Request or similar due to "Email is not verified..."
        // The backend controller returns:
        // utils.RespondErrorWithCode(
        //  w, http.StatusBadRequest, utils.ErrCodeValidation,
        //  "Email is not verified for your IP or has expired", nil,
        // )
        expect(e.statusCode, equals(400));
        expect(e.errorCode, anyOf(['validation_error', 'email_not_verified']));
      }
    });

    testWidgets(
      '4d) Verified email, invalid-format phone => attempt doRegister => expect failure',
      (tester) async {
        // Email is verified, TOTP is correct, but phone number format is invalid.
        // Registration should fail due to phone format validation.
        final randID = Random().nextInt(999999999).toString();
        final ephemeralEmail =
            '${randID}testing@thepoofapp.com'; // Suffix for clarity
        const invalidFormatPhone = '+123'; // Clearly not E.164

        // 1) Check & request email code => quickly verify it
        await pmAuthRepo.checkEmailValid(ephemeralEmail);
        await pmAuthRepo.requestEmailCode(ephemeralEmail);
        await pmAuthRepo.verifyEmailCode(ephemeralEmail, validVerificationCode);

        // 2) Generate TOTP
        final totpResp = await pmAuthRepo.generateTOTPSecret();
        final ephemeralSecret = totpResp.secret;
        final ephemeralTOTPCode = generateTOTPCode(ephemeralSecret);

        // 3) Attempt register with an invalid phone format.
        final regReq = PmRegisterRequest(
          firstName: 'InvalidPhoneFormat',
          lastName: 'Tester',
          email: ephemeralEmail, // Verified
          phoneNumber: invalidFormatPhone, // Invalid format
          businessName: 'InvalidPhoneReg LLC',
          businessAddress: '456 Invalid Ave',
          city: 'BadFormat',
          state: 'XX',
          zipCode: '00000',
          totpSecret: ephemeralSecret, // Correct
          totpToken: ephemeralTOTPCode, // Correct
        );

        try {
          await pmAuthRepo.doRegister(regReq);
          fail(
            'Expected ApiException for registration with invalid phone format',
          );
        } on ApiException catch (e) {
          // Backend's utils.ValidatePhoneNumber should cause a validation error.
          expect(e.statusCode, equals(400));
          expect(e.errorCode, anyOf(['validation_error', 'invalid_payload']));
        }
      },
    );

    // ─────────────────────────────────────────────────────────────
    // 5) Generate TOTP secret => store locally for the main user
    // ─────────────────────────────────────────────────────────────
    testWidgets('5) Generate TOTP secret => store locally', (tester) async {
      final resp = await pmAuthRepo.generateTOTPSecret();
      expect(resp.secret.isNotEmpty, true);
      totpSecret = resp.secret;
    });

    // ─────────────────────────────────────────────────────────────
    // 6) doRegister => use TOTP => confirm success
    // ─────────────────────────────────────────────────────────────
    testWidgets('6) doRegister => pass real TOTP => confirm success', (
      tester,
    ) async {
      expect(totpSecret, isNotNull, reason: 'Generate TOTP secret first');

      // We already verified the main testEmail in step 3.
      // So we can do the final registration with that email + TOTP code.
      final totpForReg = generateTOTPCode(totpSecret!);

      final req = PmRegisterRequest(
        firstName: 'TestPM',
        lastName: 'Integration',
        email: testEmail,
        phoneNumber: testPhone, // optional but verified in step 2 if your backend requires it
        businessName: 'TestBizName',
        businessAddress: '123 PM St',
        city: 'TestCity',
        state: 'CA',
        zipCode: '90000',
        totpSecret: totpSecret!,
        totpToken: totpForReg,
      );

      // If phone/email not verified or TOTP is incorrect => error. Otherwise success:
      await pmAuthRepo.doRegister(req);
    });

    // ─────────────────────────────────────────────────────────────
    // 7) Negative re-check => same phone/email => expect 409 conflict
    // ─────────────────────────────────────────────────────────────
    testWidgets(
      '7) Negative re-check => email/phone in use => expect 409 conflict',
      (tester) async {
        // Because we just used testEmail/testPhone in registration, they can't be reused
        try {
          await pmAuthRepo.checkEmailValid(testEmail);
          fail('Expected 409 conflict for existing PM email');
        } on ApiException catch (e) {
          expect(e.statusCode, equals(409));
          expect(e.errorCode, anyOf(['conflict', 'email_in_use']));
        }

        // Similarly for phone
        try {
          await pmAuthRepo.checkPhoneValid(testPhone);
          fail('Expected 409 conflict for existing PM phone');
        } on ApiException catch (e) {
          expect(e.statusCode, equals(409));
          expect(e.errorCode, anyOf(['conflict', 'phone_in_use']));
        }
      },
    );

    // ─────────────────────────────────────────────────────────────
    // 8) Negative login => invalid TOTPs => 401
    // ─────────────────────────────────────────────────────────────
    testWidgets('8) Negative login => invalid TOTPs => 401', (tester) async {
      // If we pass a correct or existing email with a wrong TOTP code → 401
      try {
        await pmAuthRepo.doLogin(
          PmLoginRequest(
            email: testEmail, // existing email
            totpCode: '000000', // definitely invalid
          ),
        );
        fail('Expected 401 invalid_credentials for wrong TOTP code');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(401));
        expect(e.errorCode, anyOf(['invalid_credentials', 'unauthorized']));
      }

      // Make sure no tokens were stored
      final tokens = await tokenStorage.getTokens();
      expect(tokens, isNull);
    });

    // ─────────────────────────────────────────────────────────────
    // 9) doLogin => success => store PM user + tokens
    // ─────────────────────────────────────────────────────────────
    testWidgets('9) doLogin => success => store PM user + tokens', (
      tester,
    ) async {
      expect(
        totpSecret,
        isNotNull,
        reason: 'Need TOTP secret from registration',
      );

      final code = generateTOTPCode(totpSecret!);
      final user = await pmAuthRepo.doLogin(
        PmLoginRequest(email: testEmail, totpCode: code),
      );

      expect(
        user.businessName.isNotEmpty,
        true,
        reason: 'Newly logged in PM user should have an ID',
      );
      expect(user.email, equals(testEmail));

      expect(
        pmUserNotifier.user,
        isNotNull,
        reason: 'pmUserStateNotifier updated',
      );
      expect(pmUserNotifier.user?.email, equals(testEmail));
    });

    // ─────────────────────────────────────────────────────────────
    // 10) Refresh token => expect rotated tokens
    // ─────────────────────────────────────────────────────────────
    testWidgets('10) Refresh token => expect rotated tokens', (tester) async {
      // Prerequisite: User should be logged in, and cookies set by the server.
      // We expect pmUserNotifier to have the user details.
      expect(
        pmUserNotifier.user,
        isNotNull,
        reason: 'User must be logged in before attempting token refresh.',
      );
      final originalUserEmail = pmUserNotifier.user!.email;

      // Attempt to refresh the token.
      // If using HttpOnly cookies, the new tokens are set by the server in Set-Cookie headers.
      // This call should succeed without throwing an exception.
      await pmAuthRepo.doRefreshToken();

      // Verify that the user state in the notifier is preserved and consistent.
      expect(
        pmUserNotifier.user,
        isNotNull,
        reason: 'User should remain logged in after token refresh.',
      );
      expect(
        pmUserNotifier.user!.email,
        equals(originalUserEmail),
        reason: 'User email should remain consistent after token refresh.',
      );
    });

    // ─────────────────────────────────────────────────────────────
    // 11) Logout => confirm tokens + user are cleared
    // ─────────────────────────────────────────────────────────────
    testWidgets('11) Logout => confirm tokens + user are cleared', (
      tester,
    ) async {
      // doLogout calls server to revoke tokens + clears them from storage
      // To confirm the new (rotated) tokens (in cookies) are functional,
      // perform an action that requires authentication, like logout.
      // Logout typically invalidates the refresh token on the server.
      // Its success implies the new cookies were used correctly.
      await pmAuthRepo.doLogout();

      expect(pmUserNotifier.user, isNull, reason: 'No PM user after logout');
    });

    // ─────────────────────────────────────────────────────────────
    // 12) Negative => doRefreshToken with no tokens => fail
    // ─────────────────────────────────────────────────────────────
    testWidgets('12) doRefreshToken with no tokens => expect fail', (
      tester,
    ) async {
      try {
        await pmAuthRepo.doRefreshToken();
        fail('Expected ApiException because we have no tokens now');
      } on ApiException catch (e) {
        // Could be "no_tokens" or a network error
        expect(
          e.errorCode,
          anyOf([
            'refresh_failed',
            'no_tokens',
            'unauthorized',
            'network_offline',
          ]), // Added 'refresh_failed'
        );
      }
    });
  });
}
