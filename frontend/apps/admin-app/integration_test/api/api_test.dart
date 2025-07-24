// frontend/apps/admin-app/integration_test/api/api_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otp/otp.dart';
import 'package:poof_admin/core/config/dev_flavor.dart';
import 'package:poof_admin/core/config/integration_test_flavor.dart';
import 'package:poof_admin/features/account/data/models/pm_models.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/auth/data/models/admin_login_request.dart';
import 'package:poof_admin/features/auth/providers/admin_auth_providers.dart';
import 'package:poof_admin/features/jobs/providers/job_providers.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:uuid/uuid.dart';

import 'test_context.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.shouldPropagateDevicePointerEvents = true;

  // --- Credentials ---
  const adminUsername = 'seedadmin';
  const adminPassword = 'P@ssword123';
  const adminTotpSecret = 'adminstatusactivestotpsecret';

  // --- Test State Variables ---
  PropertyManagerAdmin? createdPm;
  PropertyAdmin? createdProperty;
  BuildingAdmin? createdBuilding;
  UnitAdmin? createdUnit;
  DumpsterAdmin? createdDumpster;
  JobDefinitionAdmin? createdJobDef;
  const uuid = Uuid();

  // --- Helper Functions ---
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

  // This setup runs ONCE for all tests in this file.
  setUpAll(() {
    // Use the dev flavor to enable real network calls.
    configureDevFlavor();
    TestContext.authRepo = TestContext.container.read(adminAuthRepositoryProvider);
    TestContext.accountRepo = TestContext.container.read(adminAccountRepositoryProvider);
    TestContext.jobsRepo = TestContext.container.read(adminJobsRepositoryProvider);
  });

 group('Admin App E2E API Flow', () {
    // --- AUTHENTICATION ---
    testWidgets('Step 1: Login and Establish Authenticated Session', (tester) async {
      // This test remains unchanged
      print('Running Step 1: Logging in as admin...');
      expect(TestContext.authRepo, isNotNull, reason: 'Auth repository must be initialized.');

      final loginCode = generateTOTPCode(adminTotpSecret);

      try {
        final loginRequest = AdminLoginRequest(
          username: adminUsername,
          password: adminPassword,
          totpCode: loginCode,
        );
        final adminUser = await TestContext.authRepo!.doLogin(loginRequest);

        expect(adminUser, isNotNull);
        expect(adminUser.username, equals(adminUsername));

        final userState = TestContext.container.read(adminUserStateNotifierProvider);
        expect(userState.adminUser, isNotNull);
        expect(userState.adminUser!.username, equals(adminUsername));

        print('Step 1 complete. Admin login successful for user: ${adminUser.username}');
      } on ApiException catch (e) {
        fail('Admin login failed with an API exception: ${e.message}');
      }
    });

    // --- MODIFICATION: HIERARCHY CREATION BROKEN INTO INDIVIDUAL STEPS ---
    testWidgets('Step 2.1: Create Property Manager', (tester) async {
      final accountRepo = TestContext.accountRepo;
      expect(accountRepo, isNotNull);

      final pmData = {
        'email': 'integration-test-${uuid.v4()}@example.com',
        'business_name': 'Integration Test PM',
        'business_address': '123 Test St',
        'city': 'Testville',
        'state': 'CA',
        'zip_code': '90210'
      };
      createdPm = await accountRepo!.createPropertyManager(pmData);
      expect(createdPm, isNotNull, reason: "Property Manager creation failed.");
    });

    testWidgets('Step 2.2: Create Property', (tester) async {
      final accountRepo = TestContext.accountRepo;
      expect(createdPm, isNotNull, reason: "Pre-requisite PM is null.");
      
      final propData = {
        'manager_id': createdPm!.id,
        'property_name': 'Integration Test Property',
        'address': '456 Test Ave',
        'city': 'Testville',
        'state': 'CA',
        'zip_code': '90210',
        'timezone': 'America/Los_Angeles',
        'latitude': 34.0522,
        'longitude': -118.2437
      };
      createdProperty = await accountRepo!.createProperty(propData);
      expect(createdProperty, isNotNull, reason: "Property creation failed.");
    });

    testWidgets('Step 2.3: Create Building', (tester) async {
      final accountRepo = TestContext.accountRepo;
      expect(createdProperty, isNotNull, reason: "Pre-requisite Property is null.");

      final buildingData = {
        'property_id': createdProperty!.id,
        'building_name': 'Building A'
      };
      createdBuilding = await accountRepo!.createBuilding(buildingData);
      expect(createdBuilding, isNotNull, reason: "Building creation failed.");
    });

    testWidgets('Step 2.4: Create Unit', (tester) async {
      final accountRepo = TestContext.accountRepo;
      expect(createdProperty, isNotNull);
      expect(createdBuilding, isNotNull);
      
      final unitData = {
        'property_id': createdProperty!.id,
        'building_id': createdBuilding!.id,
        'unit_number': '101',
        'tenant_token': uuid.v4()
      };
      createdUnit = await accountRepo!.createUnit(unitData);
      expect(createdUnit, isNotNull, reason: "Unit creation failed.");
    });

    testWidgets('Step 2.5: Create Dumpster', (tester) async {
      final accountRepo = TestContext.accountRepo;
      expect(createdProperty, isNotNull);
      
      final dumpsterData = {
        'property_id': createdProperty!.id,
        'dumpster_number': 'D1',
        'latitude': 34.0520,
        'longitude': -118.2430
      };
      createdDumpster = await accountRepo!.createDumpster(dumpsterData);
      expect(createdDumpster, isNotNull, reason: "Dumpster creation failed.");
    });

    testWidgets('Step 2.6: Create Job Definition', (tester) async {
      final jobsRepo = TestContext.jobsRepo;
      expect(createdPm, isNotNull);
      expect(createdProperty, isNotNull);
      expect(createdBuilding, isNotNull);
      expect(createdDumpster, isNotNull);
          // Construct time values based on the current date, just like the app's UI logic does.
      // This ensures the payload format matches what the backend expects.
      final now = DateTime.now();
      final earliestStartTime = DateTime(now.year, now.month, now.day, 18, 0, 0).toUtc();
      final latestStartTime = DateTime(now.year, now.month, now.day, 22, 0, 0).toUtc();

      final dailyEstimates = List.generate(7, (index) => {
        'day_of_week': index,
        'base_pay': 25.0,
        'estimated_time_minutes': 60,
      });

      // MODIFICATION: Added optional fields to more closely match the UI payload
      // This is a more robust payload.
      final jobDefData = {
        'manager_id': createdPm!.id,
        'property_id': createdProperty!.id,
        'title': 'Daily Test Service',
        'description': 'A test service created via integration test.',
        'assigned_building_ids': [createdBuilding!.id],
        'dumpster_ids': [createdDumpster!.id],
        'frequency': 'DAILY',
        'weekdays': <int>[], // Empty for DAILY frequency
        'start_date': DateTime.now().toIso8601String(),
        'earliest_start_time': earliestStartTime.toIso8601String(),
        'latest_start_time': latestStartTime.toIso8601String(),
        'skip_holidays': false,
        'completion_rules': {
          'proof_photos_required': true,
        },
        'daily_pay_estimates': dailyEstimates,
      };
      createdJobDef = await jobsRepo!.createJobDefinition(jobDefData);
      expect(createdJobDef, isNotNull, reason: "Job Definition creation failed.");
    });
    
    // --- UPDATE TEST ---
    testWidgets('Step 3: Update Entities', (tester) async {
      // This test remains largely the same
      final accountRepo = TestContext.accountRepo;
      expect(createdPm, isNotNull);
      expect(createdProperty, isNotNull);

      // Update PM
      final updatedPm = await accountRepo!.updatePropertyManager({ 'id': createdPm!.id, 'business_name': 'Integration Test PM (Updated)', });
      expect(updatedPm.businessName, 'Integration Test PM (Updated)');

      // Update Property
      final updatedProperty = await accountRepo.updateProperty({ 'id': createdProperty!.id, 'property_name': 'Integration Test Property (Updated)', });
      expect(updatedProperty.propertyName, 'Integration Test Property (Updated)');
    });

    // --- MODIFICATION: DELETION BROKEN INTO INDIVIDUAL STEPS ---
    testWidgets('Step 4.1: Delete Job Definition', (tester) async {
      final jobsRepo = TestContext.jobsRepo;
      expect(createdJobDef, isNotNull);
      await jobsRepo!.deleteJobDefinition({'id': createdJobDef!.id});
    });

    testWidgets('Step 4.2: Delete Dumpster', (tester) async {
      final accountRepo = TestContext.accountRepo;
      expect(createdDumpster, isNotNull);
      await accountRepo!.deleteDumpster({'id': createdDumpster!.id});
    });

    testWidgets('Step 4.3: Delete Unit', (tester) async {
      final accountRepo = TestContext.accountRepo;
      expect(createdUnit, isNotNull);
      await accountRepo!.deleteUnit({'id': createdUnit!.id});
    });

    testWidgets('Step 4.4: Delete Building', (tester) async {
      final accountRepo = TestContext.accountRepo;
      expect(createdBuilding, isNotNull);
      await accountRepo!.deleteBuilding({'id': createdBuilding!.id});
    });

    testWidgets('Step 4.5: Delete Property', (tester) async {
      final accountRepo = TestContext.accountRepo;
      expect(createdProperty, isNotNull);
      await accountRepo!.deleteProperty({'id': createdProperty!.id});
    });

    testWidgets('Step 4.6: Delete Property Manager', (tester) async {
      final accountRepo = TestContext.accountRepo;
      expect(createdPm, isNotNull);
      await accountRepo!.deletePropertyManager({'id': createdPm!.id});
    });

  });
}