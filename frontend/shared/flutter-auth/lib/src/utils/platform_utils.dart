// lib/src/utils/platform_utils.dart

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Enumerates the recognized Flutter platforms for your headers.
enum FlutterPlatform {
  web,
  android,
  ios,
  unknown,
}

/// Returns a platform enum so we can set "android", "ios", or "web" in headers.
FlutterPlatform getCurrentPlatform() {
  if (kIsWeb) {
    return FlutterPlatform.web;
  }
  try {
    if (Platform.isAndroid) return FlutterPlatform.android;
    if (Platform.isIOS) return FlutterPlatform.ios;
  } catch (_) {
    // E.g. running tests on desktop where Platform is not recognized
  }
  return FlutterPlatform.unknown;
}

