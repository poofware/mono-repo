// lib/features/properties/providers/property_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_pm/core/config/config.dart';
import 'package:poof_pm/core/providers/auth_controller_provider.dart';
import '../data/api/account_api.dart';
import '../data/models/mock_property_data.dart';
import '../data/models/property_model.dart';
import '../data/repositories/account_repository.dart';

// 1. API Provider
final propertiesApiProvider = Provider<PropertiesApi>((ref) {
  return PropertiesApi(
    tokenStorage: NoOpTokenStorage(),
    onAuthLost: () => ref.read(authControllerProvider).handleAuthLost(),
  );
});

// 2. Repository Provider (NEW)
final propertiesRepositoryProvider = Provider<PropertiesRepository>((ref) {
  final api = ref.watch(propertiesApiProvider);
  return PropertiesRepository(propertiesApi: api);
});

// 3. Data Fetching Provider (was mock, now real)
final propertiesProvider = FutureProvider<List<Property>>((ref) {
  // MODIFIED: Check for testMode and return mock data if enabled.
  final config = PoofPMFlavorConfig.instance;
  if (config.testMode) {
    return Future.delayed(
      const Duration(milliseconds: 300),
      () => MockPropertyData.properties,
    );
  }

  // This now correctly depends on the repository for non-test modes.
  final propertiesRepo = ref.watch(propertiesRepositoryProvider);
  return propertiesRepo.fetchProperties();
});

// Keep these for filtering UI if needed
final propertyFilterProvider = StateProvider<String>((ref) => '');

final filteredPropertiesProvider = Provider<List<Property>>((ref) {
  final propertiesAsyncValue = ref.watch(propertiesProvider);
  final filter = ref.watch(propertyFilterProvider);

  return propertiesAsyncValue.when(
    data: (properties) {
      if (filter.isEmpty) {
        return properties;
      }
      return properties.where((property) {
        final searchTerm = filter.toLowerCase();
        return property.name.toLowerCase().contains(searchTerm) ||
               property.address.toLowerCase().contains(searchTerm);
      }).toList();
    },
    loading: () => [],
    error: (err, stack) => [],
  );
});