// @Skip('Temporarily disabled – remove this line to re-enable')

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:collection/collection.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:otp/otp.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart'
    show ApiException, SecureTokenStorage, BaseTokenStorage;
import 'package:poof_worker/core/config/config.dart';
import 'package:poof_worker/features/auth/data/api/worker_auth_api.dart';
import 'package:poof_worker/features/auth/data/models/models.dart';
import 'package:poof_worker/features/auth/data/repositories/worker_auth_repository.dart';
import 'package:poof_worker/features/account/state/worker_state_notifier.dart';

import 'package:poof_worker/features/jobs/data/api/worker_jobs_api.dart';
import 'package:poof_worker/features/jobs/data/repositories/worker_jobs_repositories.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';

// Helper function to check if a job is startable right now.
// It parses the service date and window times to compare against the current time.
bool _isJobStartableNow(JobInstance job) {
  try {
    final now = DateTime.now();
    
    // 1. Check if the service date is today.
    final serviceDate = DateFormat('yyyy-MM-dd').parse(job.serviceDate);
    final today = DateTime(now.year, now.month, now.day);
    if (serviceDate.year != today.year || serviceDate.month != today.month || serviceDate.day != today.day) {
      return false;
    }

    // 2. Parse start and end times.
    final startTimeParts = job.workerServiceWindowStart.split(':');
    final endTimeParts = job.workerServiceWindowEnd.split(':');

    if (startTimeParts.length != 2 || endTimeParts.length != 2) return false;

    // 3. Create full DateTime objects for comparison.
    final startDateTime = DateTime(
      today.year,
      today.month,
      today.day,
      int.parse(startTimeParts[0]),
      int.parse(startTimeParts[1]),
    );

    var endDateTime = DateTime( // Make endDateTime mutable
      today.year,
      today.month,
      today.day,
      int.parse(endTimeParts[0]),
      int.parse(endTimeParts[1]),
    );

    // If the end time is before the start time, it means the window crosses midnight.
    if (endDateTime.isBefore(startDateTime)) {
      endDateTime = endDateTime.add(const Duration(days: 1));
    }
    
    // 4. Check if current time is within the window.
    return now.isAfter(startDateTime) && now.isBefore(endDateTime);
  } catch (e) {
    print('Error parsing job time window: $e');
    return false;
  }
}

void main() {
  // Required for plugin usage in integration tests.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------
  //  Shared TOTP generator
  // ---------------------------------------------------------------
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

  // ---------------------------------------------------------------
  //  Variables for a single, seeded, active worker and jobs
  // ---------------------------------------------------------------
  late BaseTokenStorage tokenStorage;
  late WorkerAuthRepository authRepo;
  late WorkerJobsRepository jobsRepo;

  // Use credentials for the fully active, seeded worker
  const seededPhone = '+15552220000';
  const seededTotpSecret = 'defaultworkerstatusactivestotpsecret';

  // This location matches your seeded property from seed.go
  final double propertyLat = 34.753042676669004;
  final double propertyLng = -86.6970825455451;
  
  // These will be initialized in setUpAll with three separate, startable jobs.
  late JobInstance happyPathJob;
  late JobInstance unacceptPathJob;
  late JobInstance cancelPathJob;

  // ---------------------------------------------------------------
  //  setUpAll: Log in and find three distinct jobs for our tests.
  // ---------------------------------------------------------------
  setUpAll(() async {
    // 1) Configure environment (dev / staging)
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    switch (env) {
      case 'staging':
        configureStagingFlavor();
        break;
      default:
        configureDevFlavor();
    }

    // 2) Initialize token storage + repos
    final workerNotifier = WorkerStateNotifier();
    tokenStorage = SecureTokenStorage();
    final workerAuthApi = WorkerAuthApi(tokenStorage: tokenStorage);
    authRepo = WorkerAuthRepository(
      authApi: workerAuthApi,
      tokenStorage: tokenStorage,
      workerNotifier: workerNotifier,
    );
    final workerJobsApi = WorkerJobsApi(tokenStorage: tokenStorage);
    jobsRepo = WorkerJobsRepository(workerJobsApi);

    // 3) Login as the seeded worker
    final loginCode = generateTOTPCode(seededTotpSecret);
    await authRepo.doLogin(LoginWorkerRequest(
      phoneNumber: seededPhone,
      totpCode: loginCode,
    ));

    // 4) Find three distinct jobs for the test flows to use.
    final openJobs = await jobsRepo.listJobs(
      lat: propertyLat,
      lng: propertyLng,
      page: 1,
      size: 50, // Fetch a large batch to increase chances of finding suitable jobs.
    );

    final suitableJobs = openJobs.results.where((job) {
      final isNearby = job.distanceMiles < 5.0; // Widen radius slightly to be safe.
      final isStartable = _isJobStartableNow(job);
      if (isStartable) print('Found startable job: ${job.instanceId}');
      return isNearby && isStartable;
    }).toList();

    print('Found ${suitableJobs.length} nearby and currently startable jobs.');
    expect(
      suitableJobs.length,
      greaterThanOrEqualTo(3),
      reason: 'This integration test suite requires at least 3 startable jobs to run reliably.'
    );

    // Assign the jobs to their respective test flows.
    happyPathJob = suitableJobs[0];
    unacceptPathJob = suitableJobs[1];
    cancelPathJob = suitableJobs[2];
    print('Chosen Job for Happy Path: ${happyPathJob.instanceId}');
    print('Chosen Job for Unaccept Path: ${unacceptPathJob.instanceId}');
    print('Chosen Job for Cancel Path: ${cancelPathJob.instanceId}');
  });

  // --------------------------------------------------------------------------
  //  HAPPY PATH E2E FLOW
  // --------------------------------------------------------------------------
  group('WorkerJobs Happy Path (Accept -> Start -> Complete)', () {
    testWidgets('1) listMyJobs => initially empty for this worker',
        (tester) async {
      final myJobs = await jobsRepo.listMyJobs(
        lat: propertyLat,
        lng: propertyLng,
        page: 1,
        size: 10,
      );
      // We only care that our specific job for this flow isn't present yet.
      expect(myJobs.results.firstWhereOrNull((j) => j.instanceId == happyPathJob.instanceId), isNull,
        reason: 'The chosen happy path job should not already be in "my jobs".');
    });

    testWidgets('2) accept the chosen job', (tester) async {
      final updated = await jobsRepo.acceptJob(
        instanceId: happyPathJob.instanceId.toString(),
        lat: propertyLat,
        lng: propertyLng,
        accuracy: 5.0,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isMock: false,
      );
      expect(updated.status.name.toLowerCase(), 'assigned');
    });

    testWidgets('3) listMyJobs => should show 1 assigned job now',
        (tester) async {
      final myJobs = await jobsRepo.listMyJobs(lat: propertyLat, lng: propertyLng);
      final found = myJobs.results.firstWhere((j) => j.instanceId == happyPathJob.instanceId,
        orElse: () => throw Exception('Accepted job not found in my jobs.'));
      expect(found.status.name.toLowerCase(), 'assigned');
    });

    testWidgets('4) start job => success because it is within the time window',
        (tester) async {
      try {
        final updated = await jobsRepo.startJob(
          instanceId: happyPathJob.instanceId.toString(),
          lat: propertyLat,
          lng: propertyLng,
          accuracy: 5.0,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isMock: false,
        );
        expect(updated.status.name.toLowerCase(), anyOf(['in_progress', 'inprogress']));
        print('Job started successfully: ${updated.instanceId}');
      } on ApiException catch (e) {
        print('DEBUG (Start Job): startJob request failed with: ${e.errorCode} / ${e.message}');
        print('DEBUG (Start Job): Current UTC time is: ${DateTime.now().toUtc()}');
        fail('startJob was expected to succeed but failed: $e');
      }
    });

    testWidgets('5) complete job – negative => fails if photos are required',
        (tester) async {
      final jobAfterStart = (await jobsRepo.listMyJobs(lat: 0, lng: 0)).results.firstWhereOrNull((j) => j.instanceId == happyPathJob.instanceId);
      if (jobAfterStart?.status != JobInstanceStatus.inProgress) {
        print('Skipping negative complete test because job is not IN_PROGRESS.');
        return;
      }

      try {
        await jobsRepo.completeJob(
          instanceId: happyPathJob.instanceId.toString(),
          lat: propertyLat,
          lng: propertyLng,
          photos: [], // No photos
        );
        fail('Complete job without photos should have failed.');
      } on ApiException catch (e) {
        print('DEBUG (Negative Complete): API call failed correctly with: ${e.errorCode}');
        expect(e.errorCode, 'no_photos_provided');
      }
    });

    testWidgets('6) complete job with dummy photo', (tester) async {
      final jobAfterStart = (await jobsRepo.listMyJobs(lat: 0, lng: 0)).results.firstWhereOrNull((j) => j.instanceId == happyPathJob.instanceId);
      if (jobAfterStart?.status != JobInstanceStatus.inProgress) {
        print('Skipping complete with photo test because job is not IN_PROGRESS.');
        return;
      }

      final tmpDir = Directory.systemTemp;
      final dummyFile = File('${tmpDir.path}/dummy_photo_test.jpg');
      await dummyFile.writeAsString('FakeImageData');

      try {
        final updated = await jobsRepo.completeJob(
          instanceId: happyPathJob.instanceId.toString(),
          lat: propertyLat,
          lng: propertyLng,
          photos: [dummyFile],
        );
        print('Job complete status: ${updated.status}');
        expect(updated.status.name.toLowerCase(), 'completed');
      } on ApiException catch (e) {
        print('completeJob with a dummy photo failed: ${e.errorCode} / ${e.message}');
        rethrow;
      } finally {
        if (await dummyFile.exists()) {
          await dummyFile.delete();
        }
      }
    });
  });

  // --------------------------------------------------------------------------
  //  UNACCEPT PATH E2E FLOW
  // --------------------------------------------------------------------------
  group('WorkerJobs Unaccept Path', () {
    testWidgets('should correctly handle the Accept -> Unaccept flow', (tester) async {
      // 1. Accept the job for this flow
      final accepted = await jobsRepo.acceptJob(
        instanceId: unacceptPathJob.instanceId.toString(),
        lat: propertyLat, lng: propertyLng, accuracy: 5.0, timestamp: DateTime.now().millisecondsSinceEpoch);
      expect(accepted.status.name.toLowerCase(), 'assigned', reason: "Job must be ASSIGNED after accepting.");

      // 2. Unaccept the job
      final unaccepted = await jobsRepo.unacceptJob(unacceptPathJob.instanceId.toString());
      print('Unaccepted job status is now: ${unaccepted.status.name}');
      expect(unaccepted.status.name.toLowerCase(), 'open', reason: "Job status should revert to OPEN after unaccepting.");

      // 3. Verify the job is no longer in the worker's "my jobs" list
      final myJobs = await jobsRepo.listMyJobs(lat: propertyLat, lng: propertyLng);
      expect(myJobs.results.any((j) => j.instanceId == unacceptPathJob.instanceId), isFalse,
        reason: "Unaccepted job should no longer be in the 'my jobs' list.");
    });
  });
  
  // --------------------------------------------------------------------------
  //  CANCEL PATH E2E FLOW
  // --------------------------------------------------------------------------
  group('WorkerJobs Cancel Path', () {
    testWidgets('should correctly handle the Accept -> Start -> Cancel flow', (tester) async {
      // 1. Accept the job for this flow
      final accepted = await jobsRepo.acceptJob(
        instanceId: cancelPathJob.instanceId.toString(),
        lat: propertyLat, lng: propertyLng, accuracy: 5.0, timestamp: DateTime.now().millisecondsSinceEpoch);
      expect(accepted.status.name.toLowerCase(), 'assigned', reason: "Job must be ASSIGNED after accepting.");

      // 2. Start the job
      final started = await jobsRepo.startJob(
        instanceId: cancelPathJob.instanceId.toString(),
        lat: propertyLat, lng: propertyLng, accuracy: 5.0, timestamp: DateTime.now().millisecondsSinceEpoch);
      expect(started.status.name.toLowerCase(), anyOf(['in_progress', 'inprogress']), reason: "Job must be IN_PROGRESS after starting.");

      // 3. Cancel the job
      final cancelledJob = await jobsRepo.cancelJob(cancelPathJob.instanceId.toString());
      print('Canceled job status is now: ${cancelledJob.status.name}');
      expect(cancelledJob.status.name.toLowerCase(), anyOf(['open', 'canceled']), reason: "Job status should be OPEN or CANCELED after canceling.");

      // 4. Verify the job is no longer in the worker's "my jobs" list
      final myJobs = await jobsRepo.listMyJobs(lat: propertyLat, lng: propertyLng);
      expect(myJobs.results.any((j) => j.instanceId == cancelPathJob.instanceId), isFalse,
        reason: "Canceled job should not be in the 'my jobs' list");
    });
  });
}

