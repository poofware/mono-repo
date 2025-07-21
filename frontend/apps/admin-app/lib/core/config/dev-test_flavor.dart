// frontend/apps/admin-app/lib/core/config/dev-test_flavor.dart

import 'package:flutter/material.dart';
import 'flavors.dart';

/// Configure the "TEST" flavor.
/// This sets testMode = true on [PoofAdminFlavorConfig], meaning no real API calls.
void configureDevTestFlavor() {
  const String configuredDomain = String.fromEnvironment('CURRENT_BACKEND_DOMAIN');
  const String apiVersion = 'v1';

  final urls = PoofAdminFlavorConfig.buildServiceUrls(
    configuredDomain: configuredDomain,
    apiVersion: apiVersion,
  );

  PoofAdminFlavorConfig(
    name: "DEV-TEST",
    color: Colors.red,
    location: BannerLocation.topStart,
    gatewayURL: urls.gatewayURL, // <-- ADD THIS
    authServiceURL: urls.authServiceURL,
    apiServiceURL: urls.apiServiceURL,
    testMode: true, // <-- Set testMode to true
  );
}