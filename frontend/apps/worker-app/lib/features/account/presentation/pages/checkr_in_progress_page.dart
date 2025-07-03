// worker-app/lib/features/account/presentation/pages/checkr_in_progress_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/presentation/widgets/welcome_button.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/providers/app_logger_provider.dart';
import 'package:poof_worker/features/account/data/models/models.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations


import '../../providers/providers.dart';
import 'checkr_invite_webview_page.dart';

/// Spinner shown while we wait for the backend to confirm the invitation.
/// A full-screen **modal WebView overlay** is injected before the first
/// frame; subsequent reopens use a slide-up animation.
class CheckrInProgressPage extends ConsumerStatefulWidget {
  const CheckrInProgressPage({super.key});

  @override
  ConsumerState<CheckrInProgressPage> createState() =>
      _CheckrInProgressPageState();
}

class _CheckrInProgressPageState extends ConsumerState<CheckrInProgressPage> {
  Timer? _pollTimer;
  late String _inviteUrl; // passed via GoRouter `extra`
  bool _overlayShown = false;
  bool _buttonBusy   = false;

  // Ensures we call allowFirstFrame() exactly once
  bool _frameReleased = false;
  void _releaseFirstFrame() {
    if (_frameReleased) return;
    _frameReleased = true;
    WidgetsBinding.instance.allowFirstFrame();
  }

  // ───────────────────────────  LIFECYCLE  ───────────────────────────
  @override
  void initState() {
    super.initState();

    // Hold first frame until we decide what to show.
    WidgetsBinding.instance.deferFirstFrame();
    _beginPolling();

    // Push the overlay in a micro-task (still before first layout frame).
    Future.microtask(() {
      if (_overlayShown || !mounted) return;

      final extra = GoRouterState.of(context).extra;
      if (extra is! String) {
        _releaseFirstFrame(); // safety
        return;
      }

      final cfg = PoofWorkerFlavorConfig.instance;
      if (cfg.testMode) {
        // In TEST mode we skip the WebView overlay entirely.
        _releaseFirstFrame();
        return;
      }

      _inviteUrl   = extra;
      _overlayShown = true;
      _showInviteOverlay(
        context,
        _inviteUrl,
        animate: false,
        firstLaunch: true,
      );
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ───────────────────────────  POLLING  ───────────────────────────
  void _beginPolling() {
    final cfg = PoofWorkerFlavorConfig.instance;

    // TEST mode ⇒ user advances manually – no auto-redirect nor overlay.
    if (cfg.testMode) {
      _releaseFirstFrame();       // release splash hold once
      return;
    }

    // Normal mode → periodic polling.
    _pollTimer =
        Timer.periodic(const Duration(milliseconds: 2500), (_) => _check());
  }

  Future<void> _check() async {
    final repo   = ref.read(workerAccountRepositoryProvider);
    final logger = ref.read(appLoggerProvider);

    try {
      final st = await repo.getCheckrStatus();
      logger.d('Checkr status: ${st.status}');
      if (st.status == CheckrFlowStatus.complete) {
        _pollTimer?.cancel();
        if (mounted) context.goNamed('CheckrInviteCompletePage');
      }
    } catch (_) {
      /* ignore transient errors */
    }
  }

  // ───────────────────────────  OVERLAY  ───────────────────────────
  Future<void> _showInviteOverlay(
    BuildContext ctx,
    String url, {
    bool animate = true,
    bool firstLaunch = false,
  }) async {
    final appLocalizations = AppLocalizations.of(ctx); // Get AppLocalizations instance
    final duration =
        animate ? const Duration(milliseconds: 300) : Duration.zero;
    final builder = animate
        ? (BuildContext _, Animation<double> anim, __, Widget child) {
            final slide = Tween(begin: const Offset(0, 1), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic))
                .animate(anim);
            return SlideTransition(position: slide, child: child);
          }
        : (BuildContext _, __, ___, Widget child) => child;

    if (firstLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _releaseFirstFrame());
    }

    await showGeneralDialog(
      context: ctx,
      barrierLabel: appLocalizations.checkrInviteWebViewBarrierLabel, // Localized barrier label
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      transitionBuilder: builder,
      pageBuilder: (_, __, ___) => Material(
        color: Theme.of(ctx).scaffoldBackgroundColor,
        child: SafeArea(
          child: CheckrInviteWebViewPage(invitationUrl: url),
        ),
      ),
    );
  }

  // ─────────────────────  “Reopen / Check again”  ─────────────────────
  Future<void> _onButtonTap() async {
    if (_buttonBusy) return;

    // Capture context before async gap
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final BuildContext capturedContext = context;

    final cfg = PoofWorkerFlavorConfig.instance;
    if (cfg.testMode) {
      router.goNamed('CheckrInviteCompletePage');
      return;
    }

    setState(() => _buttonBusy = true);
    await _check(); // may already be complete
    if (!mounted) return;

    // Still incomplete ⇒ fetch fresh URL & reopen overlay with animation.
    final repo = ref.read(workerAccountRepositoryProvider);
    try {
      final invite   = await repo.createCheckrInvitation();
      _inviteUrl     = invite.invitationUrl;
      if (mounted) _showInviteOverlay(context, _inviteUrl);
    } on ApiException catch (e) {
      if (!capturedContext.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(userFacingMessage(capturedContext, e))),
      );
    } catch (e) {
      if (!capturedContext.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(capturedContext).loginUnexpectedError(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _buttonBusy = false);
    }
  }

  // ───────────────────────────  UI  ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                Text(
                  appLocalizations.checkrInProgressPageMessage,
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  appLocalizations.checkrInProgressPageCheckStatusPrompt,
                  style: TextStyle(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                WelcomeButton(
                  text: _buttonBusy
                      ? appLocalizations.checkrInProgressPageCheckingButton
                      : appLocalizations.checkrInProgressPageCheckAgainButton,
                  onPressed: _buttonBusy ? null : _onButtonTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

