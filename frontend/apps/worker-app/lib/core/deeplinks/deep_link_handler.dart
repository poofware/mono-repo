// lib/core/deeplinks/deep_link_handler.dart

import 'package:go_router/go_router.dart';

/// Minimal contract implemented by each feature that owns deep links.
///
/// * [canHandle]: Does this handler own this path?
/// * [requiresAuth]: Is authentication mandatory for *this* URI?
/// * [handle]: Perform the navigation or side effects when invoked.
abstract interface class DeepLinkHandler {
  /// Return true if this handler is responsible for [uri].
  bool canHandle(Uri uri);

  /// Return true if the user must be authenticated to handle [uri].
  bool requiresAuth(Uri uri);

  /// Called once by the coordinator when it's time to process the link.
  /// Typically calls `router.push(...)` or does any other logic required.
  Future<void> handle(Uri uri, GoRouter router);
}

