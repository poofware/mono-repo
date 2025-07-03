// lib/core/config/flavors.dart

import 'dart:io' show Platform;
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter/material.dart';

class PoofWorkerFlavorConfig {
  static PoofWorkerFlavorConfig? _instance;
  static PoofWorkerFlavorConfig get instance => _instance!;

  final String authServiceURL;
  final String apiServiceURL;
  final String baseUrl;
  final String gcpSdkKey;

  /// If true, we skip real logic for things like attestation or real API calls.
  /// Currently used to bypass real network calls in your DEV-TEST environment.
  final bool testMode;

  /// If true, then we expect the app to perform real device attestation calls
  /// on Android/iOS. If false, it does "dummy" (fake) attestation tokens.
  final bool realDeviceAttestation;

  /// A banner with the flavor name & color
  late final FlavorConfig flavorConfig;

  PoofWorkerFlavorConfig({
    String? name,
    Color color = Colors.red,
    BannerLocation location = BannerLocation.topStart,
    required this.authServiceURL,
    required this.apiServiceURL,
    required this.baseUrl,
    required this.gcpSdkKey,
    this.testMode = false,
    this.realDeviceAttestation = false,
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

  /// A helper that returns different localhost URLs depending on the platform
  static String getLocalHostForEmulator({int port = 8080}) {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:$port';
    }
    return 'http://127.0.0.1:$port';
  }
}
