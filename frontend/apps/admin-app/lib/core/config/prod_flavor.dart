// frontend/apps/admin-app/lib/core/config/prod_flavor.dart

import 'package:flutter/material.dart';
import 'flavors.dart';

void configureProdFlavor() {
  const String apiVersion = 'v1';

  // --- MODIFICATION START ---
  // Add the gatewayURL to the production configuration.
  PoofAdminFlavorConfig(
    name: "", // or "PROD" if you still want to see it
    color: Colors.green,
    location: BannerLocation.topStart,
    gatewayURL: 'https://thepoofapp.com', // <-- ADD THIS
    authServiceURL: 'https://thepoofapp.com/auth/$apiVersion',
    apiServiceURL: 'https://thepoofapp.com/api/$apiVersion',
  );
  // --- MODIFICATION END ---
}