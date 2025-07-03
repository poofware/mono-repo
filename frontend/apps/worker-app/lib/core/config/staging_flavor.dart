import 'package:flutter/material.dart';
import 'flavors.dart';

void configureStagingFlavor() {
  const baseUrl = String.fromEnvironment('CURRENT_BACKEND_DOMAIN');
  if (baseUrl.isEmpty) {
    throw Exception('CURRENT_BACKEND_DOMAIN is not set. Please set it in your build configuration.');
  }
  const String apiVersion = 'v1';

  const gcpSdkKey = String.fromEnvironment('GCP_SDK_KEY');
  if (gcpSdkKey.isEmpty) {
    throw Exception('GCP_SDK_KEY is not set. Please set it in your build configuration.');
  }

  PoofWorkerFlavorConfig(
    name: "STAGING",
    color: Colors.orange,
    location: BannerLocation.topStart,
    authServiceURL: "https://$baseUrl/auth/$apiVersion",
    apiServiceURL: "https://$baseUrl/api/$apiVersion",
    baseUrl: "https://$baseUrl",
    gcpSdkKey: gcpSdkKey,
    realDeviceAttestation: true,
  );
}
