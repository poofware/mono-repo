import 'package:flutter/material.dart';
import 'flavors.dart';

void configureProdFlavor() {
  const String apiVersion = 'v1';

  PoofAdminFlavorConfig(
    name: "", // or "PROD" if you still want to see it
    color: Colors.green,
    location: BannerLocation.topStart,
    authServiceURL: 'https://thepoofapp.com/auth/$apiVersion',
    apiServiceURL: 'https://thepoofapp.com/api/$apiVersion',
  );
}

