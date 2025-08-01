// @Skip('Temporarily disabled – remove this line to re-enable')

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

import 'package:poof_worker/features/account/data/api/worker_account_api.dart';
import 'package:poof_worker/features/account/data/repositories/worker_account_repository.dart';
import 'package:poof_worker/features/account/data/models/models.dart';

// NEW import for WorkerStateNotifier
import 'package:poof_worker/features/account/state/worker_state_notifier.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String testEmail;
  late String testPhone;
  late BaseTokenStorage tokenStorage;
  late WorkerAuthRepository authRepo;
  late WorkerAccountRepository accountRepo;

  // NEW: We'll hold a WorkerStateNotifier for both authRepo and accountRepo
  late WorkerStateNotifier workerNotifier;

  // Persist the TOTP secret for the whole test‑run.
  String? totpSecret;

  const validVerificationCode = '999999';
  const invalidVerificationCode = '888888';

  String generateTOTPCode(String secret) {
    return OTP.generateTOTPCodeString(
      secret,
      DateTime.now().millisecondsSinceEpoch,
      length: 6,
      interval: 30,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Setup once for the entire integration suite
  // ─────────────────────────────────────────────────────────────────────
  setUpAll(() async {
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'staging':
        configureStagingFlavor();
        break;
      default:
        configureDevFlavor();
    }

    // Generate random suffix for unique user
    final rand = Random().nextInt(999999999);
    final unique = rand.toString();
    testEmail = '${unique}testing@thepoofapp.com';
    final phoneDigits = rand.toString().padLeft(10, '0');
    testPhone = '+999$phoneDigits';

    // Create the workerNotifier for storing Worker data
    workerNotifier = WorkerStateNotifier();

    // 1) Auth side: WorkerAuthApi + Secure Storage + Repo
    tokenStorage = SecureTokenStorage();
    final workerAuthApi = WorkerAuthApi(tokenStorage: tokenStorage);
    authRepo = WorkerAuthRepository(
      authApi: workerAuthApi,
      tokenStorage: tokenStorage,
      workerNotifier: workerNotifier,
    );

    // 2) Instantiate the WorkerAccountApi/Repository, also providing the same workerNotifier
    final workerAccountApi = WorkerAccountApi(tokenStorage: tokenStorage);
    accountRepo = WorkerAccountRepository(
      workerAccountApi,
      workerNotifier,
    );

    // --- PHONE FIRST ---
    // 3) Request SMS code => negative => positive
    await authRepo.requestSMSCode(testPhone);
    try {
      await authRepo.verifySMSCode(testPhone, invalidVerificationCode);
      fail('Expected error for invalid SMS code.');
    } on ApiException catch (e) {
      // For invalid/expired code, we return 401 + code="unauthorized"
      expect(e.statusCode, equals(401));
      expect(e.errorCode, equals('unauthorized'));
    }
    await authRepo.verifySMSCode(testPhone, validVerificationCode);

    // 4) Generate TOTP secret
    final totpResponse = await authRepo.generateTOTPSecret();
    totpSecret = totpResponse.secret;

    // 5) Register new user with TOTP
    final regTOTP = generateTOTPCode(totpSecret!);
    await authRepo.doRegister(
      RegisterWorkerRequest(
        firstName: 'AccountFlow',
        lastName: 'Tester',
        email: testEmail,
        phoneNumber: testPhone,
        totpSecret: totpSecret!,
        totpToken: regTOTP,
      ),
    );

    // 6) Email verification => negative => positive
    await authRepo.requestEmailCode(testEmail);
    try {
      await authRepo.verifyEmailCode(testEmail, invalidVerificationCode);
      fail('Expected error for invalid email code.');
    } on ApiException catch (e) {
      expect(e.statusCode, equals(401));
      expect(e.errorCode, equals('unauthorized'));
    }
    await authRepo.verifyEmailCode(testEmail, validVerificationCode);

    // 7) Login with TOTP code
    final loginTOTP = generateTOTPCode(totpSecret!);
    await authRepo.doLogin(
      LoginWorkerRequest(
        phoneNumber: testPhone,
        totpCode: loginTOTP,
      ),
    );

    // 8) Submit personal info to complete setup
    await accountRepo.submitPersonalInfo(
      const SubmitPersonalInfoRequest(
        streetAddress: '987 Worker Lane',
        city: 'AccountCity',
        state: 'NY',
        zipCode: '12345',
        vehicleYear: 2022,
        vehicleMake: 'MakeX',
        vehicleModel: 'ModelY',
      ),
    );
  });

  // ─────────────────────────────────────────────────────────────────────
  // Actual tests
  // ─────────────────────────────────────────────────────────────────────
  group('WorkerAccountApi Integration Tests (Stripe + Checkr)', () {
    // -----------------------   Worker   -----------------------
    testWidgets('Get Worker – success', (tester) async {
      final worker = await accountRepo.getWorker();
      expect(worker.state, isNotEmpty);
      expect(worker.email, testEmail);
    });

    // -------------------------------------------------------------------------
    // NEW TEST: Patch Worker – success
    // -------------------------------------------------------------------------
    testWidgets('Patch Worker – success', (tester) async {
      // We'll change the 'city' field to verify the patch
      const newCity = 'PatchCity123';
      final updated = await accountRepo.patchWorker(
        WorkerPatchRequest(city: newCity),
      );
      expect(updated.city, equals(newCity));

      // Now fetch worker again to confirm it persisted
      final fetchedAgain = await accountRepo.getWorker();
      expect(fetchedAgain.city, equals(newCity));
    });

    // -----------------------   Stripe   -----------------------
    testWidgets('Stripe Connect flow URL', (tester) async {
      final url = await accountRepo.getStripeConnectFlowUrl();
      expect(url, allOf([isNotEmpty, startsWith('https://')]));
    });

    testWidgets('Stripe Connect flow status', (tester) async {
      final status = await accountRepo.getStripeConnectFlowStatus();
      expect(status, isNotEmpty);
    });

    testWidgets('Stripe IDV flow URL', (tester) async {
      final url = await accountRepo.getStripeIdentityFlowUrl();
      expect(url, allOf([isNotEmpty, startsWith('https://')]));
    });

    testWidgets('Stripe IDV flow status', (tester) async {
      final status = await accountRepo.getStripeIdentityFlowStatus();
      expect(status, isNotEmpty);
    });

    // -----------------------   Checkr   -----------------------
    late CheckrInvitationResponse invitation;

    testWidgets('Create Checkr invitation', (tester) async {
      invitation = await accountRepo.createCheckrInvitation();
      expect(invitation.invitationUrl, allOf([isNotEmpty, startsWith('https://')]));
      expect(invitation.message.toLowerCase(), contains('checkr'));
    });

    testWidgets('Checkr status – expect incomplete', (tester) async {
      final statusResp = await accountRepo.getCheckrStatus();
      expect(statusResp.status, CheckrFlowStatus.incomplete);
    });

    testWidgets('Checkr report ETA – expect null', (tester) async {
      final etaResp = await accountRepo.getCheckrReportEta('America/Chicago');
      expect(etaResp.reportEta, isNull);
    });

    testWidgets('Checkr outcome – expect unknown', (tester) async {
      final worker = await accountRepo.getCheckrOutcome();
      expect(worker.checkrReportOutcome, CheckrReportOutcome.unknown);
    });

    // -----------------------   Token handling   -----------------------
    testWidgets('Missing tokens → ApiException(no_tokens)', (tester) async {
      // Simulate expired / deleted tokens
      await tokenStorage.clearTokens();

      try {
        await accountRepo.getStripeConnectFlowUrl();
        fail('Expected ApiException due to missing tokens');
      } on ApiException catch (e) {
        expect(e.errorCode, 'no_tokens');
      }

      // Re‑login for any later tests
      await authRepo.doLogin(
        LoginWorkerRequest(
          phoneNumber: testPhone,
          totpCode: generateTOTPCode(totpSecret!),
        ),
      );
    });
  });
}
