// lib/core/config/flavors.dart

import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter/material.dart';

class PoofAdminFlavorConfig {
  static PoofAdminFlavorConfig? _instance;
  static PoofAdminFlavorConfig get instance => _instance!;

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

  static ({String authServiceURL, String apiServiceURL}) buildServiceUrls({
    required String configuredDomain,
    required String apiVersion,
  }) {
    final String baseApiUrl = configuredDomain.isNotEmpty ? 'https://$configuredDomain' : '';
    final String authUrl = '$baseApiUrl/auth/$apiVersion';
    final String apiUrl = '$baseApiUrl/api/$apiVersion';

    if (configuredDomain.isNotEmpty) {
      debugPrint('[PoofAdminFlavorConfig] Using ABSOLUTE backend path: $configuredDomain');
    } else {
      debugPrint('[PoofAdminFlavorConfig] Using RELATIVE backend paths (derived from empty domain)');
    }
    return (authServiceURL: authUrl, apiServiceURL: apiUrl);
  }
}