// lib/core/presentation/utils/url_launcher_utils.dart

import 'package:url_launcher/url_launcher.dart';

/// Pure, context-free utility
/// Attempts to launch a URL and returns `true` on success and `false` on failure.
/// This function will not crash and can be called from anywhere (providers, services, etc.).
Future<bool> tryLaunchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return false;
}
