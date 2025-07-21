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

    // ... The rest of your tests remain unchanged ...
    // --- ACCOUNT MANAGEMENT ---
    testWidgets('Step 2: Create Full Hierarchy (PM, Property, Building, Unit, Dumpster, JobDef)', (tester) async {
      final accountRepo = TestContext.accountRepo;
      final jobsRepo = TestContext.jobsRepo;
      expect(accountRepo, isNotNull, reason: 'Account repository must be available from auth test.');
      expect(jobsRepo, isNotNull, reason: 'Jobs repository must be available from auth test.');

      // Create Property Manager
      final pmData = { 'email': 'integration-test-${uuid.v4()}@example.com', 'business_name': 'Integration Test PM', 'business_address': '123 Test St', 'city': 'Testville', 'state': 'CA', 'zip_code': '90210' };
      createdPm = await accountRepo!.createPropertyManager(pmData);
      expect(createdPm, isNotNull);

      // Create Property
      final propData = { 'manager_id': createdPm!.id, 'property_name': 'Integration Test Property', 'address': '456 Test Ave', 'city': 'Testville', 'state': 'CA', 'zip_code': '90210', 'timezone': 'America/Los_Angeles', 'latitude': 34.0522, 'longitude': -118.2437 };
      createdProperty = await accountRepo.createProperty(propData);
      expect(createdProperty, isNotNull);

      // Create Building
      final buildingData = { 'property_id': createdProperty!.id, 'building_name': 'Building A' };
      createdBuilding = await accountRepo.createBuilding(buildingData);
      expect(createdBuilding, isNotNull);

      // Create Unit
      final unitData = { 'property_id': createdProperty!.id, 'building_id': createdBuilding!.id, 'unit_number': '101', 'tenant_token': uuid.v4() };
      createdUnit = await accountRepo.createUnit(unitData);
      expect(createdUnit, isNotNull);

      // Create Dumpster
      final dumpsterData = { 'property_id': createdProperty!.id, 'dumpster_number': 'D1', 'latitude': 34.0520, 'longitude': -118.2430 };
      createdDumpster = await accountRepo.createDumpster(dumpsterData);
      expect(createdDumpster, isNotNull);

      // Create Job Definition
      final jobDefData = { 'manager_id': createdPm!.id, 'property_id': createdProperty!.id, 'title': 'Daily Test Service', 'assigned_building_ids': [createdBuilding!.id], 'dumpster_ids': [createdDumpster!.id], 'frequency': 'DAILY', 'start_date': DateTime.now().toIso8601String(), 'earliest_start_time': '2025-01-01T18:00:00Z', 'latest_start_time': '2025-01-01T22:00:00Z', 'daily_pay_estimates': List.generate(7, (i) => {'day_of_week': i, 'base_pay': 25.0, 'estimated_time_minutes': 60}), };
      createdJobDef = await jobsRepo!.createJobDefinition(jobDefData);
      expect(createdJobDef, isNotNull);
    });

    testWidgets('Step 3: Update Entities', (tester) async {
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

    testWidgets('Step 4: Delete Hierarchy in Reverse Order', (tester) async {
        final accountRepo = TestContext.accountRepo;
        final jobsRepo = TestContext.jobsRepo;
        expect(createdJobDef, isNotNull);
        expect(createdDumpster, isNotNull);
        expect(createdUnit, isNotNull);
        expect(createdBuilding, isNotNull);
        expect(createdProperty, isNotNull);
        expect(createdPm, isNotNull);

        await jobsRepo!.deleteJobDefinition({'id': createdJobDef!.id});
        await accountRepo!.deleteDumpster({'id': createdDumpster!.id});
        await accountRepo.deleteUnit({'id': createdUnit!.id});
        await accountRepo.deleteBuilding({'id': createdBuilding!.id});
        await accountRepo.deleteProperty({'id': createdProperty!.id});
        await accountRepo.deletePropertyManager({'id': createdPm!.id});
    });
  });
}