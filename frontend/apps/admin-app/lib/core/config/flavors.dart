// frontend/apps/admin-app/lib/core/config/flavors.dart

import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter/material.dart';

class PoofAdminFlavorConfig {
  static PoofAdminFlavorConfig? _instance;
  static PoofAdminFlavorConfig get instance => _instance!;

  final String gatewayURL; // <-- ADD THIS
  final String authServiceURL;
  final String apiServiceURL;

  /// A banner with the flavor name & color
  late final FlavorConfig flavorConfig;

  /// If true, the entire app is in "test mode" and should skip real API calls
  final bool testMode;

  PoofAdminFlavorConfig({
    String? name,
    Color color = Colors.red,
    BannerLocation location = BannerLocation.topStart,
    required this.gatewayURL, // <-- ADD THIS
    required this.authServiceURL,
    required this.apiServiceURL,
    this.testMode = false,
  }) {
    flavorConfig = FlavorConfig(
      name: name,
      color: color,
      location: location,
      variables: const {},
    );
    _instance = this;
  }

  String get name => flavorConfig.name ?? '';
  Color get color => flavorConfig.color;
  BannerLocation get location => flavorConfig.location;

   static ({String gatewayURL, String authServiceURL, String apiServiceURL}) buildServiceUrls({
    required String configuredDomain,
    required String apiVersion,
  }) {
    if (configuredDomain.isEmpty) {
      debugPrint('[PoofAdminFlavorConfig] Using RELATIVE backend paths (derived from empty domain)');
      return (gatewayURL: '', authServiceURL: '/auth/$apiVersion', apiServiceURL: '/api/$apiVersion');
    }

    // FIX: Determine protocol based on domain
    final bool isLocal = configuredDomain.contains('localhost') || configuredDomain.contains('127.0.0.1');
    final String protocol = isLocal ? 'http' : 'https';
    final String baseApiUrl = '$protocol://$configuredDomain';

    final String authUrl = '$baseApiUrl/auth/$apiVersion';
    final String apiUrl = '$baseApiUrl/api/$apiVersion';

    if (isLocal) {
      debugPrint('[PoofAdminFlavorConfig] Using LOCAL backend path: $baseApiUrl');
    } else {
      debugPrint('[PoofAdminFlavorConfig] Using ABSOLUTE backend path: $baseApiUrl');
    }
    return (gatewayURL: baseApiUrl, authServiceURL: authUrl, apiServiceURL: apiUrl); // <-- MODIFY RETURN VALUE
  }
}