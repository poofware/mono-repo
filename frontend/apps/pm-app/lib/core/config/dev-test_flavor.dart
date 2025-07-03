import 'package:flutter/material.dart';
import 'flavors.dart';

void configureDevTestFlavor() {
  const String configuredDomain = String.fromEnvironment('CURRENT_BACKEND_DOMAIN');
  const String apiVersion = 'v1';

  final urls = PoofPMFlavorConfig.buildServiceUrls(
    configuredDomain: configuredDomain, // Will be empty if --dart-define gives an empty string
    apiVersion: apiVersion,
  );

  PoofPMFlavorConfig(
    // name: "DEV-TEST", // Optional: uncomment if you want a banner
    color: Colors.red,
    location: BannerLocation.topStart,
    authServiceURL: urls.authServiceURL,
    apiServiceURL: urls.apiServiceURL,
    testMode: true,
  );
}
