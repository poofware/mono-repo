// pm-app/lib/core/config/flavors.dart

import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter/material.dart'; // For debugPrint

class PoofPMFlavorConfig {
  static PoofPMFlavorConfig? _instance;
  static PoofPMFlavorConfig get instance => _instance!;

  final String authServiceURL;
  final String apiServiceURL;
  final bool testMode;
  late final FlavorConfig flavorConfig;

  // Constructor remains the same
  PoofPMFlavorConfig({
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

  static String getLocalHostBaseUrl({int port = 8080}) {
    return 'http://127.0.0.1:$port';
  }

  static ({String authServiceURL, String apiServiceURL}) buildServiceUrls({
    required String configuredDomain,
    required String apiVersion, // Pass apiVersion if it can vary, or use a const
  }) {
    final String baseApiUrl = configuredDomain.isNotEmpty ? 'https://$configuredDomain' : '';
    final String authUrl = '$baseApiUrl/auth/$apiVersion';
    final String apiUrl = '$baseApiUrl/api/$apiVersion';

    if (configuredDomain.isNotEmpty) {
      debugPrint('[PoofPMFlavorConfig] Using ABSOLUTE backend path: $configuredDomain');
    } else {
      debugPrint('[PoofPMFlavorConfig] Using RELATIVE backend paths (derived from empty domain for $configuredDomain)');
    }
    return (authServiceURL: authUrl, apiServiceURL: apiUrl);
  }
}
