// NEW FILE
import 'package:flutter/material.dart';
import 'flavors.dart';

/// Configure the "IntegrationTest" flavor.
/// This sets testMode = false and points to the local backend.
void configureIntegrationTestFlavor() {
  // For integration tests, we connect to the backend running locally.
  // The docker-compose setup typically exposes the gateway on port 8000.
  const String backendDomain = 'localhost:8000';
  const String apiVersion = 'v1';

  final urls = PoofAdminFlavorConfig.buildServiceUrls(
    configuredDomain: backendDomain,
    apiVersion: apiVersion,
  );

  PoofAdminFlavorConfig(
    name: "API-TEST",
    color: Colors.purple,
    location: BannerLocation.topStart,
    gatewayURL: urls.gatewayURL,
    authServiceURL: urls.authServiceURL,
    apiServiceURL: urls.apiServiceURL,
    testMode: false, // <-- Use REAL API calls
  );
}