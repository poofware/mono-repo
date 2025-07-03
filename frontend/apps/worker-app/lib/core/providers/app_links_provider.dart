// lib/core/providers/app_links_provider.dart
//
// Hooks App Links into Riverpod and forwards every URI
// to the DeepLinkCoordinator.

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';
import 'package:poof_worker/core/deeplinks/deep_link_coordinator.dart';

final appLinksProvider = Provider<AppLinks>((ref) => AppLinks());

/// One global coordinator (instantiated once).
final deepLinkCoordinatorProvider = Provider<DeepLinkCoordinator>(
  (ref) => DeepLinkCoordinator(ref),
);

/// Call this exactly once after `GoRouter` is created and
/// ProviderScope is ready (e.g. inside `initState()` of MyApp).
Future<void> initAppLinks(WidgetRef ref, GoRouter router) async {
  final log = ref.read(appLoggerProvider);
  final appLinks = ref.read(appLinksProvider);
  final coordinator = ref.read(deepLinkCoordinatorProvider);

  // Initial (cold‑start) link
  try {
    final initial = await appLinks.getInitialLink();
    if (initial != null) {
      log.d('AppLinks: initial link = $initial');
      await coordinator.processUri(initial, router, fromColdStart: true);
    }
  } catch (e, s) {
    log.e('AppLinks: error reading initial link: $e\n$s');
  }

  // Stream of subsequent links
  appLinks.uriLinkStream.listen(
    (uri) {
      log.d('AppLinks: stream link = $uri');
      coordinator.processUri(uri, router, fromColdStart: false);
    },
    onError: (err) => log.e('AppLinks: stream error: $err'),
  );
}

