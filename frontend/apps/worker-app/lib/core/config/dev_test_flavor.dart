import 'package:flutter/material.dart';
import 'flavors.dart';

/// Configure the "TEST" flavor.
/// This sets testMode = true on [PoofWorkerFlavorConfig], meaning no real API calls.
void configureDevTestFlavor() {
  const baseUrl = String.fromEnvironment('CURRENT_BACKEND_DOMAIN');
  if (baseUrl.isEmpty) {
    throw Exception('CURRENT_BACKEND_DOMAIN is not set. Please set it in your build configuration.');
  }
  const gcpSdkKey = String.fromEnvironment('GCP_SDK_KEY');
  if (gcpSdkKey.isEmpty) {
    throw Exception('GCP_SDK_KEY is not set. Please set it in your build configuration.');
  }

  PoofWorkerFlavorConfig(
   // name: "DEV-TEST",
    color: Colors.red,
    location: BannerLocation.topStart,
    authServiceURL: 'https://$baseUrl/auth',
    apiServiceURL: 'https://$baseUrl/api',
    baseUrl: 'https://$baseUrl',
    gcpSdkKey: gcpSdkKey,
    testMode: true, // <-- Set testMode to true
    realDeviceAttestation: false,
  );
}
