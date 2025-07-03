@Skip('Temporarily disabled – remove this line to re-enable')

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otp/otp.dart';

import 'package:poof_worker/core/config/config.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart'
    show ApiException, SecureTokenStorage, BaseTokenStorage;

import 'package:poof_worker/features/auth/data/api/worker_auth_api.dart';
import 'package:poof_worker/features/auth/data/repositories/worker_auth_repository.dart';
import 'package:poof_worker/features/auth/data/models/models.dart';

// NEW import for WorkerStateNotifier
import 'package:poof_worker/features/account/state/worker_state_notifier.dart';

void main() {
  // Allows plugins like flutter_secure_storage to work in integration tests.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String testEmail;
  late String testPhone;
  late BaseTokenStorage tokenStorage;
  late WorkerAuthRepository workerAuthRepo;

  // We'll store the TOTP secret from "generateTOTPSecret" for registration & login.
  String? totpSecret;

  // Our WorkerStateNotifier for tracking the logged-in worker in-memory.
  late WorkerStateNotifier workerNotifier;

  // Some predefined codes your backend uses in test mode
  const validVerificationCode = '999999';
  const invalidVerificationCode = '888888';

  // Helper: generate a current TOTP code for the secret at "now"
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
    // Configure environment (dev/staging) based on build/test invocation:
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'staging':
        configureStagingFlavor();
        break;
      default:
        configureDevFlavor();
    }

    // Generate random suffix for unique email & phone
    final rand = Random().nextInt(999999999);
    final unique = rand.toString();

    testEmail = '${unique}testing@thepoofapp.com';
    final phoneDigits = rand.toString().padLeft(10, '0');
    testPhone = '+999$phoneDigits';

    // Create WorkerStateNotifier and token storage
    workerNotifier = WorkerStateNotifier();
    tokenStorage = SecureTokenStorage();

    // Build the WorkerAuthApi + WorkerAuthRepository
    final workerAuthApi = WorkerAuthApi(tokenStorage: tokenStorage);
    workerAuthRepo = WorkerAuthRepository(
      authApi: workerAuthApi,
      tokenStorage: tokenStorage,
      workerNotifier: workerNotifier,
    );
  });

  tearDownAll(() async {
    // Clear tokens if you want each test run to start fresh.
    await tokenStorage.clearTokens();
  });

  group('WorkerAuth Integration Tests (E2E) - Phone-First Flow', () {
    // ─────────────────────────────────────────────────────────────
    // 0) Negative validations -> expect 400 "validation_error"
    // ─────────────────────────────────────────────────────────────

    testWidgets('0.1) Validate invalid email => expect 400', (tester) async {
      // We'll pass a guaranteed invalid email format.
      const invalidEmail = 'notanemail@foo';
      try {
        await workerAuthRepo.checkEmailValid(invalidEmail);
        fail('Expected a 400 with "validation_error" for invalid email format');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(400));
        expect(e.errorCode, equals('validation_error'));
      }
    });

    testWidgets('0.2) Validate invalid phone => expect 400', (tester) async {
      // We'll pass a definitely invalid phone format to your E.164-limited endpoint.
      const invalidPhone = '+12345'; // Not enough digits, or clearly invalid
      try {
        await workerAuthRepo.checkPhoneValid(invalidPhone);
        fail('Expected a 400 with "validation_error" for invalid phone format');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(400));
        expect(e.errorCode, equals('validation_error'));
      }
    });

    // ─────────────────────────────────────────────────────────────
    // 1) Check phone is unused => request code => negative & positive verifies
    // ─────────────────────────────────────────────────────────────
    testWidgets('1) Check phone is unused => request code => negative & positive verifies',
        (tester) async {
      // 1a) Confirm phone is not "in use" => no exception => 200 OK from server
      await workerAuthRepo.checkPhoneValid(testPhone);

      // 1b) Request the phone code
      await workerAuthRepo.requestSMSCode(testPhone);

      // 1c) Negative verify => expect error (invalid code)
      try {
        await workerAuthRepo.verifySMSCode(testPhone, invalidVerificationCode);
        fail('Expected ApiException for invalid SMS code');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(401));
        expect(e.errorCode, equals('unauthorized'));
      }

      // 1d) Positive verify => no error
      await workerAuthRepo.verifySMSCode(testPhone, validVerificationCode);
    });

    // ─────────────────────────────────────────────────────────────
    // 2) Generate TOTP secret
    // ─────────────────────────────────────────────────────────────
    testWidgets('2) Generate TOTP secret', (WidgetTester tester) async {
      final response = await workerAuthRepo.generateTOTPSecret();
      expect(response.secret.isNotEmpty, true, reason: 'Should provide TOTP secret');
      totpSecret = response.secret;
    });

    // ─────────────────────────────────────────────────────────────
    // 3) Register user with TOTP code
    // ─────────────────────────────────────────────────────────────
    testWidgets('3) Register user with TOTP code', (WidgetTester tester) async {
      expect(totpSecret, isNotNull, reason: 'TOTP secret must be generated first.');

      // Produce a valid TOTP code from that secret
      final totpForRegistration = generateTOTPCode(totpSecret!);

      final registerRequest = RegisterWorkerRequest(
        firstName: 'TestFirst',
        lastName: 'TestLast',
        email: testEmail,
        phoneNumber: testPhone,
        totpSecret: totpSecret!,
        totpToken: totpForRegistration,
      );

      // Should succeed with no exception
      await workerAuthRepo.doRegister(registerRequest);
    });

    // ─────────────────────────────────────────────────────────────
    // 4) Request email code, negative verify => positive verify
    // ─────────────────────────────────────────────────────────────
    testWidgets('4) Request email code, negative verify => positive verify',
        (WidgetTester tester) async {
      // Request a code for the newly registered email
      await workerAuthRepo.requestEmailCode(testEmail);

      // Verify with an invalid code first => expect error
      try {
        await workerAuthRepo.verifyEmailCode(testEmail, invalidVerificationCode);
        fail('Expected ApiException for invalid email code.');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(401));
        expect(e.errorCode, equals('unauthorized'));
      }

      // Then verify with the known "valid" test code
      await workerAuthRepo.verifyEmailCode(testEmail, validVerificationCode);
    });

    // ─────────────────────────────────────────────────────────────
    // 5) Login with TOTP => then check phone/email "valid" => expect 409 since used
    // ─────────────────────────────────────────────────────────────
    testWidgets('5) Login with TOTP => then check phone/email "valid" => expect 409 since used',
        (WidgetTester tester) async {
      expect(totpSecret, isNotNull, reason: 'Need the TOTP secret from registration');
      final loginTOTP = generateTOTPCode(totpSecret!);

      // Store tokens + set worker in notifier
      await workerAuthRepo.doLogin(
        LoginWorkerRequest(
          phoneNumber: testPhone,
          totpCode: loginTOTP,
        ),
      );

      final w = workerNotifier.state.worker;
      expect(w, isNotNull, reason: 'Worker should be set after login');

      final tokens = await tokenStorage.getTokens();
      expect(tokens, isNotNull, reason: 'Tokens should be stored');

      // Now phone + email are "used" => checkPhoneValid / checkEmailValid => 409 conflict
      try {
        await workerAuthRepo.checkPhoneValid(testPhone);
        fail('Expected 409 conflict for phone in use');
      } on ApiException catch (e) {
        expect(e.statusCode, 409);
        expect(e.errorCode, 'conflict');
      }

      try {
        await workerAuthRepo.checkEmailValid(testEmail);
        fail('Expected 409 conflict for email in use');
      } on ApiException catch (e) {
        expect(e.statusCode, 409);
        expect(e.errorCode, 'conflict');
      }
    });

    // ─────────────────────────────────────────────────────────────
    // 6) Negative login with invalid TOTP code
    // ─────────────────────────────────────────────────────────────
    testWidgets('6) Negative login with invalid TOTP code', (WidgetTester tester) async {
      // Logout first to clear Worker + tokens
      await workerAuthRepo.doLogout();
      expect(workerNotifier.state.worker, isNull, reason: 'Worker cleared after logout');

      // Attempt login with obviously invalid credentials
      try {
        await workerAuthRepo.doLogin(
          const LoginWorkerRequest(
            phoneNumber: '+9990000000000', // fake phone
            totpCode: '000000', // definitely invalid
          ),
        );
        fail('Expected ApiException for invalid TOTP code or phone');
      } on ApiException catch (e) {
        // The backend sets code="invalid_credentials" for incorrect TOTP or phone
        expect(e.statusCode, equals(401));
        expect(e.errorCode, equals('invalid_credentials'));
      }

      // Ensure no tokens were saved
      final tokens = await tokenStorage.getTokens();
      expect(tokens, isNull);
    });

    // ─────────────────────────────────────────────────────────────
    // 7) Logout flow
    // ─────────────────────────────────────────────────────────────
    testWidgets('7) Logout flow', (WidgetTester tester) async {
      // Re-login with a fresh TOTP
      expect(totpSecret, isNotNull);
      final newCode = generateTOTPCode(totpSecret!);
      await workerAuthRepo.doLogin(
        LoginWorkerRequest(
          phoneNumber: testPhone,
          totpCode: newCode,
        ),
      );
      final tokensPreLogout = await tokenStorage.getTokens();
      expect(tokensPreLogout, isNotNull);

      // Now logout
      await workerAuthRepo.doLogout();
      expect(workerNotifier.state.worker, isNull, reason: 'Worker cleared after logout');

      final tokensPostLogout = await tokenStorage.getTokens();
      expect(tokensPostLogout, isNull, reason: 'Tokens cleared after logout');
    });

    // ─────────────────────────────────────────────────────────────
    // 8) Refresh-token rotation (doRefreshToken)
    // ─────────────────────────────────────────────────────────────
    testWidgets('8) Refresh-token rotation', (WidgetTester tester) async {
      // 8a) Log-in (so we have an initial Access/Refresh pair)
      expect(totpSecret, isNotNull);
      final loginCode = generateTOTPCode(totpSecret!);

      await workerAuthRepo.doLogin(
        LoginWorkerRequest(
          phoneNumber: testPhone,
          totpCode: loginCode,
        ),
      );

      final initialTokens = await tokenStorage.getTokens();
      expect(initialTokens, isNotNull, reason: 'Tokens must exist before refresh');

      final oldAccess  = initialTokens!.accessToken;
      final oldRefresh = initialTokens.refreshToken;

      // 8b) Invoke the repository helper -- this calls the
      //     `/worker/refresh_token` endpoint under the hood.
      await workerAuthRepo.doRefreshToken(); // throws on failure

      // 8c) Expect new tokens have replaced the old pair
      final newTokens = await tokenStorage.getTokens();
      expect(newTokens, isNotNull, reason: 'Tokens should still exist after refresh');
      expect(newTokens!.accessToken,  isNot(equals(oldAccess)),
          reason: 'Access-token should be rotated');
      expect(newTokens.refreshToken, isNot(equals(oldRefresh)),
          reason: 'Refresh-token should be rotated');

      // 8d) Worker should still be considered logged-in
      expect(workerNotifier.state.worker, isNotNull,
          reason: 'Worker should remain in memory after refresh');
    });
  });
}

