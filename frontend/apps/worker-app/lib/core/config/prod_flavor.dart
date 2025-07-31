import 'package:flutter/material.dart';
import 'flavors.dart';

void configureProdFlavor() {
  const gcpSdkKey = String.fromEnvironment('GCP_SDK_KEY');
  if (gcpSdkKey.isEmpty) {
    throw Exception('GCP_SDK_KEY is not set. Please set it in your build configuration for production.');
  }

  PoofWorkerFlavorConfig(
    name: "", // or "PROD" if you still want to see it
    color: Colors.green,
    location: BannerLocation.topStart,
    authServiceURL: 'https://thepoofapp.com/auth',
    apiServiceURL: 'https://thepoofapp.com/api',
    baseUrl: 'https://thepoofapp.com',
    gcpSdkKey: gcpSdkKey,
    realDeviceAttestation: true,
  );
}
