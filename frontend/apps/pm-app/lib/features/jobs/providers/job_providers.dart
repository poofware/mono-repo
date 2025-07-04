import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_pm/core/config/config.dart';
import 'package:poof_pm/core/providers/auth_controller_provider.dart';

import '../data/api/jobs_api.dart';
import '../data/models/building_subset.dart';
import '../data/models/job_instance_pm.dart';
import '../data/models/job_status.dart';
import '../data/models/property_model_subset.dart';
import 'package:poof_pm/features/jobs/data/repositories/jobs_repostiory.dart';
import 'package:poof_pm/features/jobs/state/jobs_fiiter_notifier.dart';
import '../state/job_history_state.dart';

// 1. API Provider (connects to the backend)
final jobsApiProvider = Provider<JobsApi>((ref) {
  return JobsApi(
    // The PM app uses cookie-based auth, so NoOpTokenStorage is correct.
    tokenStorage: NoOpTokenStorage(),
    onAuthLost: () => ref.read(authControllerProvider).handleAuthLost(),
  );
});

// 2. Repository Provider (abstracts the API layer)
final jobsRepositoryProvider = Provider<JobsRepository>((ref) {
  final api = ref.watch(jobsApiProvider);
  return JobsRepository(jobsApi: api);
});

// 3. Filter State Provider (manages the state of the UI filter controls)
final jobFiltersProvider = StateNotifierProvider<JobFiltersNotifier, JobHistoryFilters>((ref) {
  return JobFiltersNotifier();
});

List<JobInstancePm> _createMockJobInstances(String propertyId) {
  final now = DateTime.now();
  final rand = Random();
  const nonCompletedStatusValues = ['missed', 'inprogress', 'open'];

  String _generateRealisticId(String prefix) {
    final randomHex = rand.nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    return '${prefix}_$randomHex';
  }

  // Generate 100 jobs, which is 2 jobs per day for the last 50 days.
  return List.generate(100, (index) {
    // `index ~/ 2` creates two jobs for each day.
    final date = now.subtract(Duration(days: index ~/ 2));

    // 99% of jobs are 'completed', 1% are a random non-completed status.
    final statusValue = rand.nextInt(100) < 99
        ? 'completed'
        : nonCompletedStatusValues[rand.nextInt(nonCompletedStatusValues.length)];

    return JobInstancePm(
      instanceId: _generateRealisticId('inst'),
      definitionId: _generateRealisticId('def'),
      propertyId: propertyId,
      serviceDate: date.toIso8601String().substring(0, 10),
      status: statusValue,
      property: PropertySubset(
        propertyId: propertyId,
        propertyName: 'Mock Property: $propertyId',
        address: '123 Mockingbird Lane',
        city: 'Mocksville',
        state: 'MC',
        zipCode: '00000',
        latitude: 34.7,
        longitude: -86.6,
      ),
      buildings: List.generate(2, (bIndex) => BuildingSubset(
        buildingId: 'bldg_mock_${bIndex}',
        name: 'Building ${String.fromCharCode(65 + bIndex)}',
        latitude: 34.7 + (bIndex * 0.01),
        longitude: -86.6 + (bIndex * 0.01),
      )),
    );
  });
}

// 4. Data Fetching Provider (fetches raw data from the API based on a propertyId)
// This is the provider that will be invalidated to trigger a refetch.
final jobsForPropertyProvider = FutureProvider.family<List<JobInstancePm>, String>((ref, propertyId) {
  final config = PoofPMFlavorConfig.instance;
  if (config.testMode) {
    return Future.delayed(const Duration(milliseconds: 800), () => _createMockJobInstances(propertyId));
  }
  final jobsRepo = ref.watch(jobsRepositoryProvider);
  return jobsRepo.fetchJobsForProperty(propertyId);
});