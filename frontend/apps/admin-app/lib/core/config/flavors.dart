// lib/core/config/flavors.dart

import 'dart:io' show Platform;
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
    this.testMode = false, // <-- Default false
  }) {
    // We still create a FlavorConfig for display
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

  /// A helper that returns different localhost URLs depending on the platform
  static String getLocalHostBaseUrl({int port = 8080}) {
    return 'http://127.0.0.1:$port';
  }
}

