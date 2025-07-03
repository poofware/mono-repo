// lib/core/deeplinks/deep_link_coordinator.dart
//
// Coordinates incoming deep‑links across the whole app, buffering protected
// links when the user is logged‑out and delivering them after login.
//
// 2025‑04‑22 – Added automatic buffer‑clear on *logout* so that no stale
// link fires after the user signs out and back in.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poof_worker/core/app_state/app_state.dart';
import 'package:poof_worker/core/providers/app_state_provider.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';

import 'deep_link_handler.dart';
import 'package:poof_worker/features/account/providers/worker_account_deep_links_provider.dart';

class DeepLinkCoordinator {
  DeepLinkCoordinator(this._ref)
      : _logger = _ref.read(appLoggerProvider) {
    // -----------------------------------------------------------------
    // Whenever the global login flag changes, flush pending links *after*
    // login, and wipe the buffer *immediately* on logout.
    // -----------------------------------------------------------------
    _ref.listen<AppStateData>(
      appStateProvider,
      (prev, next) {
        // ─── Signed‑in → deliver any buffered protected link ───────────
        if (prev?.isLoggedIn == false && next.isLoggedIn == true) {
          _deliverPendingIfAny();
        }
        // ─── Signed‑out → discard buffer so it won't fire later ────────
        if (prev?.isLoggedIn == true && next.isLoggedIn == false) {
          _clearPending();
        }
      },
    );
  }

  // ─── Dependencies ──────────────────────────────────────────────────
  final Ref _ref;
  final dynamic _logger;

  // Registered handlers (add new ones here)
  late final List<DeepLinkHandler> _handlers = [
    _ref.read(workerAccountDeepLinkHandlerProvider),
    _UnknownHandler(_logger),
  ];

  bool get _isLoggedIn => _ref.read(appStateProvider).isLoggedIn;

  // ─── Single‑slot buffer ────────────────────────────────────────────
  Uri?              _pendingUri;
  DeepLinkHandler?  _pendingHandler;
  GoRouter?         _routerRef;          // remembers last router seen

  // ───────────────────────────────────────────────────────────────────
  //  PUBLIC ENTRY POINT
  // ───────────────────────────────────────────────────────────────────
  Future<void> processUri(
    Uri uri,
    GoRouter router, {
    required bool fromColdStart,
  }) async {
    _logger.i('DeepLinkCoordinator: link=${uri.path} coldStart=$fromColdStart');
    _routerRef = router;

    final handler = _handlers.firstWhere((h) => h.canHandle(uri));

    // ---------- Public link: execute immediately ----------
    if (!handler.requiresAuth(uri)) {
      await handler.handle(uri, router);
      return;
    }

    // ---------- Protected link ----------
    if (_isLoggedIn) {
      await handler.handle(uri, router);
    } else {
      // Buffer exactly one link; ignore further ones until it’s delivered.
      if (_pendingUri == null) {
        _pendingUri     = uri;
        _pendingHandler = handler;
        _logger.i('DeepLinkCoordinator: buffered protected link.');
      } else {
        _logger.w('DeepLinkCoordinator: already buffering – ignoring new link.');
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────
  //  PRIVATE HELPERS
  // ───────────────────────────────────────────────────────────────────
  Future<void> _deliverPendingIfAny() async {
    if (_pendingUri == null || _pendingHandler == null || _routerRef == null) {
      return;
    }

    final uri     = _pendingUri!;
    final handler = _pendingHandler!;
    final router  = _routerRef!;

    // Clear *before* calling so a thrown error doesn’t loop endlessly.
    _clearPending();

    _logger.i('DeepLinkCoordinator: delivering buffered link → $uri');
    try {
      await handler.handle(uri, router);
    } catch (e, s) {
      _logger.e('DeepLinkCoordinator: error delivering link: $e\n$s');
    }
  }

  void _clearPending() {
    if (_pendingUri != null) {
      _logger.i('DeepLinkCoordinator: cleared buffered link on logout.');
    }
    _pendingUri = null;
    _pendingHandler = null;
  }
}

/// Fallback handler – logs and safely ignores unknown URLs.
class _UnknownHandler implements DeepLinkHandler {
  _UnknownHandler(this._logger);
  final dynamic _logger;

  @override
  bool canHandle(Uri uri) => true;

  @override
  bool requiresAuth(Uri uri) => false;

  @override
  Future<void> handle(Uri uri, GoRouter router) async =>
      _logger.w('UnknownHandler: unhandled URI $uri');
}

