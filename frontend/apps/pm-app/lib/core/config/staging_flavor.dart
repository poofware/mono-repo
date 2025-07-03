import 'package:flutter/material.dart';
import 'flavors.dart';

void configureStagingFlavor() {
  const String configuredDomain = String.fromEnvironment('CURRENT_BACKEND_DOMAIN');
  const String apiVersion = 'v1';

  final urls = PoofPMFlavorConfig.buildServiceUrls(
    configuredDomain: configuredDomain,
    apiVersion: apiVersion,
  );

  PoofPMFlavorConfig(
    name: "STAGING",
    color: Colors.orange,
    location: BannerLocation.topStart,
    authServiceURL: urls.authServiceURL,
    apiServiceURL: urls.apiServiceURL,
    testMode: false, // Typically false for staging
  );
}
