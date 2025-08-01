@Skip('Temporarily disabled – remove this line to re-enable')

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otp/otp.dart';

import 'package:poof_worker/core/config/config.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart'
    show ApiException, SecureTokenStorage, BaseTokenStorage;

// Auth imports for login
import 'package:poof_worker/features/auth/data/api/worker_auth_api.dart';
import 'package:poof_worker/features/auth/data/repositories/worker_auth_repository.dart';
import 'package:poof_worker/features/auth/data/models/models.dart';
import 'package:poof_worker/features/account/state/worker_state_notifier.dart';

// Earnings imports for the actual test
import 'package:poof_worker/features/earnings/data/api/earnings_api.dart';
import 'package:poof_worker/features/earnings/data/models/earnings_models.dart';
import 'package:poof_worker/features/earnings/data/repositories/earnings_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // For authentication
  late BaseTokenStorage tokenStorage;
  late WorkerAuthRepository authRepo;
  late WorkerStateNotifier workerNotifier;

  // For the actual test
  late EarningsRepository earningsRepo;

  // Credentials for the seeded "active" worker
  const seededWorkerPhone = '+15552220000';
  const seededWorkerTotpSecret = 'defaultworkerstatusactivestotpsecretokay';

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

  setUpAll(() async {
    // 1. Configure environment
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'staging':
        configureStagingFlavor();
        break;
      default:
        configureDevFlavor();
    }

    // 2. Initialize auth components
    workerNotifier = WorkerStateNotifier();
    tokenStorage = SecureTokenStorage();
    final workerAuthApi = WorkerAuthApi(tokenStorage: tokenStorage);
    authRepo = WorkerAuthRepository(
      authApi: workerAuthApi,
      tokenStorage: tokenStorage,
      workerNotifier: workerNotifier,
    );

    // 3. Login as the seeded worker
    final loginTOTP = generateTOTPCode(seededWorkerTotpSecret);
    await authRepo.doLogin(
      LoginWorkerRequest(
        phoneNumber: seededWorkerPhone,
        totpCode: loginTOTP,
      ),
    );

    // 4. Initialize earnings components (they will now use the stored tokens)
    final earningsApi = EarningsApi(tokenStorage: tokenStorage);
    earningsRepo = EarningsRepository(earningsApi);
  });

  tearDownAll(() async {
    // Clear tokens after tests are done
    await tokenStorage.clearTokens();
  });

  group('WorkerEarningsApi Integration Tests', () {
    testWidgets('Get Earnings Summary - success', (tester) async {
      final EarningsSummary summary = await earningsRepo.getEarningsSummary();

      // --- High-level structural assertions ---
      expect(summary, isNotNull);
      expect(summary.twoMonthTotal, isA<double>());
      expect(summary.currentWeek, isNotNull,
          reason: 'Current week should always be present.');
      expect(summary.pastWeeks, isA<List<WeeklyEarnings>>());

      // --- Logical consistency checks (decoupled from specific amounts) ---
      final calculatedTotal = (summary.currentWeek?.weeklyTotal ?? 0.0) +
          summary.pastWeeks.fold<double>(0.0, (sum, w) => sum + w.weeklyTotal);

      expect(summary.twoMonthTotal, closeTo(calculatedTotal, 0.01),
          reason: 'TwoMonthTotal should be the sum of current and past weeks.');

      expect(summary.pastWeeks, isNotEmpty,
          reason: 'Seeded data should include past weeks.');

      // Based on the backend seeders (jobs-service and earnings-service),
      // we expect exactly two past paid weeks.
      expect(summary.pastWeeks.length, 2,
          reason: 'Backend seeder should create 2 past paid weeks.');

      // --- Verify properties of each past week ---
      for (final week in summary.pastWeeks) {
        expect(week.payoutStatus, equals(PayoutStatus.paid),
            reason: 'Seeded past weeks should have a status of PAID.');

        final expectedJobCount =
            week.dailyBreakdown.fold<int>(0, (sum, d) => sum + d.jobCount);
        expect(week.jobCount, equals(expectedJobCount),
            reason: 'Weekly job count should equal sum of daily job counts.');

        expect(week.weeklyTotal, greaterThan(0),
            reason: 'Weekly total for a past paid week should be positive.');

        // Verify daily breakdown within the week
        for (final day in week.dailyBreakdown) {
          final expectedDailyTotal =
              day.jobs.fold<double>(0.0, (sum, j) => sum + j.pay);
          expect(day.totalAmount, closeTo(expectedDailyTotal, 0.01),
              reason: "Daily total should be the sum of its jobs' pay.");
          expect(day.jobCount, day.jobs.length,
              reason:
                  'Daily job count should equal the number of jobs in its list.');
        }
      }

      // --- Verify properties of the current week ---
      final currentWeek = summary.currentWeek!;
      expect(currentWeek.payoutStatus, equals(PayoutStatus.current));
      expect(currentWeek.weeklyTotal, greaterThanOrEqualTo(0.0),
          reason:
              "Current week's total can be zero if no jobs have been completed yet.");

      // --- Verify sorting of past weeks (most recent first) ---
      if (summary.pastWeeks.length > 1) {
        for (int i = 0; i < summary.pastWeeks.length - 1; i++) {
          expect(
              summary.pastWeeks[i]
                  .weekStartDate
                  .isAfter(summary.pastWeeks[i + 1].weekStartDate),
              isTrue,
              reason:
                  'Past weeks should be sorted from most recent to oldest.');
        }
      }
    });

    testWidgets('Get Earnings Summary - Unauthorized when logged out',
        (tester) async {
      // Clear tokens to simulate being logged out
      await tokenStorage.clearTokens();

      try {
        await earningsRepo.getEarningsSummary();
        fail('Expected ApiException due to missing tokens');
      } on ApiException catch (e) {
        expect(e.errorCode, 'no_tokens');
      }

      // Re-login for any subsequent tests in the group if necessary
      final loginTOTP = generateTOTPCode(seededWorkerTotpSecret);
      await authRepo.doLogin(
        LoginWorkerRequest(
          phoneNumber: seededWorkerPhone,
          totpCode: loginTOTP,
        ),
      );
    });
  });
}
