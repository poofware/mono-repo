// worker-app/lib/features/jobs/state/jobs_state_notifier.dart
//
// FINAL VERSION:
// - Includes start, complete, and cancel job logic.
// - `fetchAllMyJobs` correctly partitions assigned vs. in-progress jobs.
// - `refreshOnlineJobsIfActive` now correctly performs a full refresh of all job lists
//   to ensure state is synchronized with the backend upon app resume.

import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'package:poof_worker/features/jobs/state/jobs_state.dart';
import 'package:poof_worker/features/jobs/data/models/job_models.dart';
import 'package:poof_worker/features/jobs/data/models/dummy_job_data.dart';
import 'package:poof_worker/features/jobs/data/repositories/worker_jobs_repositories.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';
import 'package:poof_worker/core/utils/location_permissions.dart';
import 'package:poof_worker/features/jobs/utils/job_photo_persistence.dart';

// NEW IMPORT for earnings
import 'package:poof_worker/features/earnings/providers/earnings_providers.dart';

class JobsNotifier extends StateNotifier<JobsState> {
  final Ref ref;
  final WorkerJobsRepository _repository;
  final PoofWorkerFlavorConfig _flavor;

  JobsNotifier(this.ref, this._repository, this._flavor)
    : super(const JobsState());

  // ─────────────────────────────────────────────────────────────────────────
  //  GO ONLINE
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> goOnline() async {
    if (state.isOnline && state.openJobs.isNotEmpty) {
      ref
          .read(appLoggerProvider)
          .d('Already online with jobs, skipping goOnline fetch.');
      return;
    }
    state = state.copyWith(
      isLoadingOpenJobs: true,
      isLoadingAcceptedJobs: true,
      clearError: true,
    );

    if (_flavor.testMode) {
      final logger = ref.read(appLoggerProvider);
      logger.d('goOnline() in test mode — setting openJobs from dummy data.');
      final open = DummyJobData.openJobs;
      final accepted = DummyJobData.acceptedJobs;
      state = state.copyWith(
        isOnline: true,
        isLoadingOpenJobs: false,
        isLoadingAcceptedJobs: false,
        openJobs: open,
        acceptedJobs: accepted,
      );
      return;
    }

    try {
      final position = await _getHighAccuracyFix();
      final logger = ref.read(appLoggerProvider);
      logger.d(
        'Fetching open jobs at lat=${position.latitude}, lng=${position.longitude}',
      );

      // Fetch both open and accepted jobs concurrently.
      final results = await Future.wait([
        _repository.listJobs(lat: position.latitude, lng: position.longitude),
        _repository.listMyJobs(lat: position.latitude, lng: position.longitude),
      ]);

      final openResp = results[0];
      final myJobsResp = results[1];

      // Partition the "my jobs" list.
      final inProgressJob = myJobsResp.results.firstWhereOrNull(
        (j) => j.status == JobInstanceStatus.inProgress,
      );
      final acceptedJobs = myJobsResp.results
          .where((j) => j.status == JobInstanceStatus.assigned)
          .toList();

      // Update state once with all results and set both loading flags to false.
      state = state.copyWith(
        isOnline: true,
        isLoadingOpenJobs: false,
        isLoadingAcceptedJobs: false,
        openJobs: openResp.results,
        acceptedJobs: acceptedJobs,
        inProgressJob: inProgressJob,
        clearInProgressJob: inProgressJob == null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingOpenJobs: false,
        isLoadingAcceptedJobs: false,
        isOnline: false,
        error: e,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  GO OFFLINE
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> goOffline() async {
    if (!state.isOnline) return;
    final logger = ref.read(appLoggerProvider);
    logger.d('goOffline() called.');

    try {
      await Future.delayed(const Duration(milliseconds: 100));
      state = state.copyWith(
        isOnline: false,
        isLoadingOpenJobs: false,
        isLoadingAcceptedJobs: false,
        openJobs: [],
        clearError: true,
      );
      logger.d('Successfully went offline. Job lists updated.');
    } catch (e) {
      state = state.copyWith(
        isLoadingOpenJobs: false,
        isLoadingAcceptedJobs: false,
        error: e,
      );
      logger.e('Error during goOffline: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  REFRESH ONLINE JOBS IF ACTIVE (called on app resume)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> refreshOnlineJobsIfActive() async {
    if (!state.isOnline) {
      ref
          .read(appLoggerProvider)
          .d('Not online, skipping job refresh on resume.');
      return;
    }

    if (state.inProgressJob != null) {
      ref
          .read(appLoggerProvider)
          .d('Job already in progress, skipping refresh.');
      return;
    }

    ref.read(appLoggerProvider).d('App resumed and online, refreshing jobs...');
    state = state.copyWith(
      isLoadingOpenJobs: true,
      isLoadingAcceptedJobs: true,
      clearError: true,
    );

    if (_flavor.testMode) {
      final open = DummyJobData.openJobs;
      final accepted = DummyJobData.acceptedJobs;
      state = state.copyWith(
        isLoadingOpenJobs: false,
        isLoadingAcceptedJobs: false,
        openJobs: open,
        acceptedJobs: accepted,
      );
      ref.read(appLoggerProvider).d('Refreshed dummy jobs.');
      return;
    }

    try {
      final position = await _getHighAccuracyFix();
      final logger = ref.read(appLoggerProvider);
      logger.d(
        'Refreshing jobs at lat=${position.latitude}, lng=${position.longitude}',
      );

      final results = await Future.wait([
        _repository.listJobs(lat: position.latitude, lng: position.longitude),
        _repository.listMyJobs(lat: position.latitude, lng: position.longitude),
      ]);

      final openResp = results[0];
      final myJobsResp = results[1];

      final inProgressJob = myJobsResp.results.firstWhereOrNull(
        (j) => j.status == JobInstanceStatus.inProgress,
      );
      final acceptedJobs = myJobsResp.results
          .where((j) => j.status == JobInstanceStatus.assigned)
          .toList();

      state = state.copyWith(
        isLoadingOpenJobs: false,
        isLoadingAcceptedJobs: false,
        openJobs: openResp.results,
        acceptedJobs: acceptedJobs,
        inProgressJob: inProgressJob,
        clearInProgressJob: inProgressJob == null,
      );

      logger.d(
        'Successfully refreshed jobs. Open: ${openResp.results.length}, Accepted: ${acceptedJobs.length}, InProgress: ${inProgressJob != null}',
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingOpenJobs: false,
        isLoadingAcceptedJobs: false,
        error: e,
      );
      ref.read(appLoggerProvider).e('Error refreshing jobs: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  FETCH ALL MY JOBS (Accepted and In-Progress)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> fetchAllMyJobs() async {
    if (state.isLoadingAcceptedJobs) {
      ref
          .read(appLoggerProvider)
          .d('Already loading accepted jobs, skipping fetchAllMyJobs.');
      return;
    }
    ref
        .read(appLoggerProvider)
        .d('Fetching all user jobs (accepted and in-progress)...');

    state = state.copyWith(isLoadingAcceptedJobs: true, clearError: true);

    if (_flavor.testMode) {
      final accepted = DummyJobData.acceptedJobs;
      state = state.copyWith(
        isLoadingAcceptedJobs: false,
        acceptedJobs: accepted,
        clearError: true,
        clearInProgressJob: true,
      );
      return;
    }

    try {
      final position = await _getHighAccuracyFix();
      final myJobsResp = await _repository.listMyJobs(
        lat: position.latitude,
        lng: position.longitude,
      );

      final inProgressJob = myJobsResp.results.firstWhereOrNull(
        (j) => j.status == JobInstanceStatus.inProgress,
      );
      final acceptedJobs = myJobsResp.results
          .where((j) => j.status == JobInstanceStatus.assigned)
          .toList();

      state = state.copyWith(
        isLoadingAcceptedJobs: false,
        acceptedJobs: acceptedJobs,
        inProgressJob: inProgressJob,
        clearInProgressJob: inProgressJob == null,
        clearError: true,
      );

      ref
          .read(appLoggerProvider)
          .d(
            'Fetched ${acceptedJobs.length} accepted and ${inProgressJob != null ? 1 : 0} in-progress job.',
          );
    } catch (e) {
      state = state.copyWith(isLoadingAcceptedJobs: false, error: e);
      ref.read(appLoggerProvider).e('Error fetching my jobs: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  ACCEPT JOB
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> acceptJob(String instanceId) async {
    final logger = ref.read(appLoggerProvider);
    logger.d('Attempting to accept job $instanceId...');

    try {
      final openJob = state.openJobs.firstWhere(
        (j) => j.instanceId == instanceId,
        orElse: () => throw Exception(
          'Job $instanceId not found in local state for acceptance.',
        ),
      );

      if (_flavor.testMode) {
        logger.d('Accepting job $instanceId in test mode.');
        await Future.delayed(const Duration(milliseconds: 300));
      } else {
        logger.d('Accepting job $instanceId in real mode.');
        final position = await _getHighAccuracyFix();
        await _repository.acceptJob(
          instanceId: instanceId,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          timestamp: position.timestamp.millisecondsSinceEpoch,
          isMock: position.isMocked,
        );
      }

      final acceptedJobInstance = openJob.copyWith(
        status: JobInstanceStatus.assigned,
      );
      final newOpenJobs = List<JobInstance>.from(state.openJobs)
        ..removeWhere((j) => j.instanceId == instanceId);
      final newAcceptedJobs = List<JobInstance>.from(state.acceptedJobs)
        ..removeWhere((j) => j.instanceId == instanceId)
        ..add(acceptedJobInstance);

      state = state.copyWith(
        openJobs: newOpenJobs,
        acceptedJobs: newAcceptedJobs,
        clearError: true,
      );
      logger.d(
        'Job $instanceId accepted successfully. Open jobs: ${newOpenJobs.length}, Accepted jobs: ${newAcceptedJobs.length}',
      );
      return true;
    } catch (e) {
      logger.e('Error accepting job $instanceId: $e');
      state = state.copyWith(error: e);
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  UNACCEPT JOB
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> unacceptJob(String instanceId) async {
    final logger = ref.read(appLoggerProvider);
    logger.d('Attempting to unaccept job $instanceId...');

    try {
      if (_flavor.testMode) {
        logger.d('Unaccepting job $instanceId in test mode.');
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        logger.d('Unaccepting job $instanceId in real mode.');
        await _repository.unacceptJob(instanceId);
      }

      final newAcceptedJobs = List<JobInstance>.from(state.acceptedJobs)
        ..removeWhere((j) => j.instanceId == instanceId);
      state = state.copyWith(acceptedJobs: newAcceptedJobs, clearError: true);
      logger.d(
        'Job $instanceId unaccepted. Accepted jobs: ${newAcceptedJobs.length}',
      );
      return true;
    } catch (e) {
      logger.e('Error unaccepting job $instanceId: $e');
      state = state.copyWith(error: e);
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  START JOB
  // ─────────────────────────────────────────────────────────────────────────
  Future<JobInstance?> startJob(String instanceId) async {
    final logger = ref.read(appLoggerProvider);
    logger.d('Attempting to start job $instanceId...');

    try {
      late final JobInstance updatedJob;

      if (_flavor.testMode) {
        logger.d('Starting job $instanceId in test mode.');
        final originalJob = state.acceptedJobs.firstWhere(
          (j) => j.instanceId == instanceId,
        );
        updatedJob = originalJob.copyWith(
          status: JobInstanceStatus.inProgress,
          checkInAt: DateTime.now(),
        );
        await Future.delayed(const Duration(milliseconds: 300));
      } else {
        final position = await _getHighAccuracyFix();
        updatedJob = await _repository.startJob(
          instanceId: instanceId,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          timestamp: position.timestamp.millisecondsSinceEpoch,
          isMock: position.isMocked,
        );
      }

      final newAcceptedJobs = List<JobInstance>.from(state.acceptedJobs)
        ..removeWhere((j) => j.instanceId == instanceId);
      state = state.copyWith(
        acceptedJobs: newAcceptedJobs,
        inProgressJob: updatedJob,
        clearError: true,
      );

      logger.d('Job $instanceId started successfully.');
      return updatedJob;
    } catch (e) {
      logger.e('Error starting job $instanceId: $e');
      state = state.copyWith(error: e);
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  CANCEL JOB
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> cancelJob(String instanceId) async {
    final logger = ref.read(appLoggerProvider);
    logger.d('Attempting to cancel job $instanceId...');
    try {
      late final JobInstance updatedJob;
      if (_flavor.testMode) {
        logger.d(
          'Cancelling job $instanceId in test mode (status is now CANCELED).',
        );
        updatedJob = state.inProgressJob!.copyWith(
          status: JobInstanceStatus.canceled,
        );
        await Future.delayed(const Duration(milliseconds: 300));
      } else {
        updatedJob = await _repository.cancelJob(instanceId);
      }

      state = state.copyWith(clearInProgressJob: true, clearError: true);

      logger.d(
        'Job $instanceId cancelled on the client. Final backend status: ${updatedJob.status}',
      );
      return true;
    } catch (e) {
      logger.e('Error cancelling job $instanceId: $e');
      state = state.copyWith(error: e);
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  VERIFY UNIT PHOTO
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> verifyUnitPhoto(String unitId, XFile photo) async {
    final logger = ref.read(appLoggerProvider);
    final job = state.inProgressJob;
    if (job == null) return false;

    logger.d('Verifying photo for unit $unitId of job ${job.instanceId}');

    final saved = await JobPhotoPersistence.savePhoto(job.instanceId, photo);

    try {
      late final JobInstance updated;
      if (_flavor.testMode) {
        await Future.delayed(const Duration(milliseconds: 300));
        final updatedBuildings = job.buildings.map((b) {
          final units = b.units.map((u) {
            if (u.unitId == unitId) {
              return UnitVerification(
                unitId: u.unitId,
                buildingId: u.buildingId,
                unitNumber: u.unitNumber,
                status: UnitVerificationStatus.verified,
                attemptCount: 0,
                failureReasons: const [],
                permanentFailure: false,
              );
            }
            return u;
          }).toList();
          return Building(
            buildingId: b.buildingId,
            name: b.name,
            latitude: b.latitude,
            longitude: b.longitude,
            units: units,
          );
        }).toList();
        updated = job.copyWith(buildings: updatedBuildings);
      } else {
        final position = await _getHighAccuracyFix();
        updated = await _repository.verifyPhoto(
          instanceId: job.instanceId,
          unitId: unitId,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          timestamp: position.timestamp.millisecondsSinceEpoch,
          isMock: position.isMocked,
          photo: File(saved.path),
        );
      }

      state = state.copyWith(inProgressJob: updated, clearError: true);
      await JobPhotoPersistence.clearPhotos(job.instanceId);
      logger.d('Unit $unitId verified successfully.');
      return true;
    } catch (e) {
      logger.e('Error verifying unit $unitId: $e');
      state = state.copyWith(error: e);
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  DUMP BAGS
  // ─────────────────────────────────────────────────────────────────────────
  Future<bool> dumpBags() async {
    final logger = ref.read(appLoggerProvider);
    final job = state.inProgressJob;
    if (job == null) return false;

    logger.d('Dumping bags for job ${job.instanceId}');

    try {
      late final JobInstance updated;
      if (_flavor.testMode) {
        await Future.delayed(const Duration(milliseconds: 300));
        updated = job;
      } else {
        final position = await _getHighAccuracyFix();
        updated = await _repository.dumpBags(
          instanceId: job.instanceId,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          timestamp: position.timestamp.millisecondsSinceEpoch,
          isMock: position.isMocked,
        );
      }

      final completed = updated.status == JobInstanceStatus.completed;
      state = state.copyWith(
        inProgressJob: completed ? null : updated,
        clearError: true,
        clearInProgressJob: completed,
      );

      if (completed) {
        ref
            .read(earningsNotifierProvider.notifier)
            .fetchEarningsSummary(force: true);
        await JobPhotoPersistence.clearPhotos(job.instanceId);
      }

      logger.d('Dump trip processed. Job completed: $completed');
      return true;
    } catch (e) {
      logger.e('Error processing dump for job ${job.instanceId}: $e');
      state = state.copyWith(error: e);
      return false;
    }
  }

  /// NEW: Clears the error from the state. Called by the UI after displaying a SnackBar.
  void clearError() {
    if (state.error != null) {
      state = state.copyWith(clearError: true);
    }
  }

  Future<Position> _getHighAccuracyFix() async {
    final ok = await ensureLocationGranted();
    if (!ok) {
      throw Exception('Location permission not granted.');
    }
    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      timeLimit: Duration(seconds: 15),
    );
    try {
      final androidSettings = AndroidSettings(
        accuracy: settings.accuracy,
        distanceFilter: settings.distanceFilter,
        timeLimit: settings.timeLimit,
        forceLocationManager: true,
      );
      return await Geolocator.getCurrentPosition(
        locationSettings: androidSettings,
      );
    } catch (e) {
      return Geolocator.getCurrentPosition(locationSettings: settings);
    }
  }
}
