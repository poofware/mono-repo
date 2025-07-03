import 'package:flutter/material.dart';
import 'flavors.dart';

void configureDevFlavor() {
  String localhost = PoofAdminFlavorConfig.getLocalHostBaseUrl(port: 8080);
  const String apiVersion = 'v1';

  PoofAdminFlavorConfig(
    name: "DEV",
    color: Colors.red,
    location: BannerLocation.topStart,
    authServiceURL: '$localhost/auth/$apiVersion',
    apiServiceURL: '$localhost/api/$apiVersion',
  );
}
