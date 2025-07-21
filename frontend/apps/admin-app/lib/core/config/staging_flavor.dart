import 'package:flutter/material.dart';
import 'flavors.dart';

void configureStagingFlavor() {
  const String apiVersion = 'v1';

  PoofAdminFlavorConfig(
    name: "STAGING",
    color: Colors.orange,
    location: BannerLocation.topStart,
    gatewayURL: 'https://staging.thepoofapp.com', 
    authServiceURL: "https://staging.thepoofapp.com/auth/$apiVersion",
    apiServiceURL: "https://staging.thepoofapp.com/api/$apiVersion",
  );
}
