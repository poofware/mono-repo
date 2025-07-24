// frontend/apps/admin-app/integration_test/api/debug_create_job_test.dart

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:otp/otp.dart';
import 'package:poof_admin/core/config/dev_flavor.dart';
import 'package:poof_admin/features/account/data/models/pm_models.dart';
import 'package:poof_admin/features/auth/data/models/admin_login_request.dart';
import 'package:poof_admin/features/jobs/data/models/job_definition_admin.dart';
import 'package:uuid/uuid.dart';
import 'package:poof_admin/features/auth/providers/admin_auth_providers.dart';
import 'package:poof_admin/features/account/providers/pm_providers.dart';
import 'package:poof_admin/features/jobs/providers/job_providers.dart';


import 'test_context.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // --- Credentials ---
  const adminUsername = 'seedadmin';
  const adminPassword = 'P@ssword123';
  const adminTotpSecret = 'adminstatusactivestotpsecret';
  const uuid = Uuid();

  // --- Helper ---
  String generateTOTPCode(String secret) => OTP.generateTOTPCodeString(secret, DateTime.now().millisecondsSinceEpoch, isGoogle: true);

  // --- Setup ---
  setUpAll(() {
    configureDevFlavor(); // Use real API calls
    // Initialize repos from the shared context by reading them once.
    TestContext.container.read(adminAuthRepositoryProvider);
    TestContext.container.read(adminAccountRepositoryProvider);
    TestContext.container.read(adminJobsRepositoryProvider);
  });

  testWidgets('DEBUG: Isolate and test job definition creation', (tester) async {
    // --- STEP 1: LOGIN ---
    print('--- DEBUG: Logging in ---');
    final loginCode = generateTOTPCode(adminTotpSecret);
    await TestContext.authRepo!.doLogin(AdminLoginRequest(
      username: adminUsername,
      password: adminPassword,
      totpCode: loginCode,
    ));
    print('--- DEBUG: Login successful ---');

    // --- STEP 2: CREATE PREREQUISITES ---
    print('--- DEBUG: Creating prerequisites (PM, Property, etc.) ---');
    final pm = await TestContext.accountRepo!.createPropertyManager({
      'email': 'debug-test-${uuid.v4()}@example.com', 'business_name': 'Debug Test PM',
      'business_address': '123 Debug St', 'city': 'Debugville', 'state': 'CA', 'zip_code': '90210'
    });
    final prop = await TestContext.accountRepo!.createProperty({
      'manager_id': pm.id, 'property_name': 'Debug Property', 'address': '456 Debug Ave',
      'city': 'Debugville', 'state': 'CA', 'zip_code': '90210', 'timezone': 'America/Los_Angeles',
      'latitude': 34.0522, 'longitude': -118.2437
    });
    final bldg = await TestContext.accountRepo!.createBuilding({'property_id': prop.id, 'building_name': 'Debug Building'});
    final dumpster = await TestContext.accountRepo!.createDumpster({'property_id': prop.id, 'dumpster_number': 'D-Debug', 'latitude': 34.0520, 'longitude': -118.2430});
    print('--- DEBUG: Prerequisites created successfully ---');

    // --- STEP 3: CONSTRUCT AND PRINT PAYLOAD ---
    print('--- DEBUG: Constructing Job Definition Payload ---');
    final now = DateTime.now();
    final earliestStartTime = DateTime(now.year, now.month, now.day, 18, 0, 0).toUtc();
    final latestStartTime = DateTime(now.year, now.month, now.day, 22, 0, 0).toUtc();

    final dailyEstimates = List.generate(7, (index) => {
      'day_of_week': index,
      'base_pay': 25.0,
      'estimated_time_minutes': 60,
    });

    final jobDefData = {
      'manager_id': pm.id,
      'property_id': prop.id,
      'title': 'Debug Daily Service',
      'assigned_building_ids': [bldg.id],
      'dumpster_ids': [dumpster.id],
      'frequency': 'DAILY',
      'start_date': now.toIso8601String(),
      'earliest_start_time': earliestStartTime.toIso8601String(),
      'latest_start_time': latestStartTime.toIso8601String(),
      'daily_pay_estimates': dailyEstimates,
      // Adding optional fields to match UI more closely
      'description': 'A job created for debugging purposes.',
      'weekdays': <int>[], // Empty for DAILY frequency
      'skip_holidays': false,
      'completion_rules': {
        'proof_photos_required': true,
      },
    };

    // This is the most important part: printing the exact JSON
    final jsonPayload = jsonEncode(jobDefData);
    print('--- DEBUG: FINAL JSON PAYLOAD TO BE SENT ---');
    print(jsonPayload);
    print('-------------------------------------------');

    // --- STEP 4: ATTEMPT CREATION ---
    JobDefinitionAdmin? createdJobDef;
    try {
      print('--- DEBUG: Sending request to create job definition... ---');
      createdJobDef = await TestContext.jobsRepo!.createJobDefinition(jobDefData);
      print('--- DEBUG: Job definition created SUCCESSFULLY! ---');
      print('--- DEBUG: Created Job ID: ${createdJobDef.id}');
    } catch (e) {
      print('--- DEBUG: FAILED to create job definition. Error: $e ---');
      fail('Job definition creation failed with error: $e');
    }

    expect(createdJobDef, isNotNull, reason: "Job Definition creation failed.");
    expect(createdJobDef.title, 'Debug Daily Service');

    // --- STEP 5: CLEANUP ---
    print('--- DEBUG: Cleaning up created entities... ---');
    await TestContext.jobsRepo!.deleteJobDefinition({'id': createdJobDef.id});
    await TestContext.accountRepo!.deleteDumpster({'id': dumpster.id});
    await TestContext.accountRepo!.deleteBuilding({'id': bldg.id});
    await TestContext.accountRepo!.deleteProperty({'id': prop.id});
    await TestContext.accountRepo!.deletePropertyManager({'id': pm.id});
    print('--- DEBUG: Cleanup complete. ---');
  });
}