import 'package:flutter/material.dart';
import 'flavors.dart';

/// Configure the "TEST" flavor.
/// This sets testMode = true on [PoofAdminFlavorConfig], meaning no real API calls.
void configureDevTestFlavor() {
  String localhost = PoofAdminFlavorConfig.getLocalHostBaseUrl(port: 8080);
  const String apiVersion = 'v1';

  PoofAdminFlavorConfig(
    name: "DEV-TEST",
    color: Colors.red,
    location: BannerLocation.topStart,
    authServiceURL: '$localhost/auth/$apiVersion',
    apiServiceURL: '$localhost/api/$apiVersion',
    testMode: true, // <-- Set testMode to true
  );
}

