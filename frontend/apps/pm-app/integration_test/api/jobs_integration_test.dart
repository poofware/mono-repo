// meta-service/pm-app/integration_test/api/jobs_integration_test.dart

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otp/otp.dart';
import 'package:poof_pm/core/config/config.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_pm/features/auth/data/api/pm_auth_api.dart';
import 'package:poof_pm/features/auth/data/models/models.dart';
import 'package:poof_pm/features/auth/data/repositories/pm_auth_repository.dart';
import 'package:poof_pm/features/auth/state/pm_user_state_notifier.dart';
import 'package:poof_pm/features/jobs/data/api/jobs_api.dart';
import 'package:poof_pm/features/jobs/data/models/list_jobs_pm_request.dart';
import 'package:poof_pm/features/jobs/data/models/job_instance_pm.dart';
import 'package:poof_pm/features/account/data/api/account_api.dart';
import 'package:poof_pm/features/account/data/models/property_model.dart';
import 'package:poof_pm/features/account/data/repositories/account_repository.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.shouldPropagateDevicePointerEvents = true;

  late PmAuthRepository pmAuthRepo;
  late JobsApi jobsApi;
  late PropertiesRepository propertiesRepo;
  String? propertyIdForTest;

  const testEmail = 'team@thepoofapp.com';
  const seededWorkerTotpSecret = 'defaultpmstatusactivestotpsecret';
  // Helper to generate a valid TOTP code
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

  // This group handles the entire setup flow as a series of tests.
  // This is more robust than a single setUpAll block, as it ensures each
  // step completes successfully before the next begins, mirroring a real user journey.
  group('PM App Setup and Login Flow', () {
    setUpAll(() {
      // This part runs once before all tests in this group.
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'staging':
        configureStagingFlavor();
        break;
      default:
        configureDevFlavor();
    }
      final tokenStorage = SecureTokenStorage(
      // Optionally give them unique key names for this test
      accessTokenKey: 'pm_access_token_test',
      refreshTokenKey: 'pm_refresh_token_test',
      );
      final pmAuthApi = PmAuthApi(
        tokenStorage: tokenStorage,
        useRealAttestation: false,
      );
      pmAuthRepo = PmAuthRepository(
        authApi: pmAuthApi,
        tokenStorage: tokenStorage,
        pmUserNotifier: PmUserStateNotifier(),
      );
      jobsApi = JobsApi(
        tokenStorage: tokenStorage,
        useRealAttestation: false,
      );
      final propertiesApi = PropertiesApi(tokenStorage: tokenStorage, useRealAttestation: false);
      propertiesRepo = PropertiesRepository(propertiesApi: propertiesApi);
    });


    
    testWidgets('Step 1: Login and Establish Authenticated Session', (tester) async {
      print('Running Step 1: Logging in...');
      expect(seededWorkerTotpSecret, isNotNull, reason: 'TOTP secret must be available for login.');
      final loginCode = generateTOTPCode(seededWorkerTotpSecret);
      try {
        await pmAuthRepo.doLogin(PmLoginRequest(email: testEmail, totpCode: loginCode));
        print('Step 1 complete. Login successful.');
      } on ApiException catch (e) {
        print('--- LOGIN FAILED ---');
        print('Status Code: ${e.statusCode}');
        print('Error Code: ${e.errorCode}');
        print('Error Message: ${e.message}');
        print('--------------------');
        fail('Login failed with an API exception.');
      }
    });

    testWidgets('Step 2: Fetch Properties to get a valid propertyId', (tester) async {
      print('Running Step 2: Fetching properties...');
      final properties = await propertiesRepo.fetchProperties();
      // The backend should automatically create a default property for a new PM.
      expect(properties, isNotEmpty, reason: 'A new PM should have at least one property created by the backend.');
      propertyIdForTest = properties.first.id;
      print('Step 5 complete. Got propertyId: $propertyIdForTest');
    });
  });

  // This group contains the actual test for the Jobs API.
  // It runs *after* the setup group has completed successfully.
  group('Jobs API Integration Tests (Requires Logged-In PM)', () {
    testWidgets('successfully fetches job instances for a property', (tester) async {
      print('Running final test: Fetching jobs for property...');
      // ARRANGE
      expect(propertyIdForTest, isNotNull, reason: 'Setup flow must complete and provide a propertyId.');
      final request = ListJobsPmRequest(propertyId: propertyIdForTest!);

      // ACT
      final response = await jobsApi.fetchJobsForProperty(request);

      // ASSERT
      expect(response, isNotNull);
      expect(response.total, isA<int>()); // Total can be 0, which is valid.
      expect(response.results, isA<List<JobInstancePm>>());

      if (response.results.isNotEmpty) {
        final firstJob = response.results.first;
        expect(firstJob, isA<JobInstancePm>());
        expect(firstJob.propertyId, equals(propertyIdForTest));
        expect(firstJob.instanceId, isNotEmpty);
        expect(firstJob.property, isNotNull);
        expect(firstJob.property.propertyName, isNotEmpty);
      } else {
        print('NOTE: The API call to fetch jobs was successful, but no job instances were returned for the new PM. This is an acceptable outcome.');
      }
      print('Jobs API test complete.');
    });
  });
}