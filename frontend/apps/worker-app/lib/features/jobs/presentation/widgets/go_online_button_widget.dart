// worker-app/lib/features/jobs/presentation/widgets/go_online_button_widget.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/features/account/providers/worker_account_repository_provider.dart';
import 'package:poof_worker/features/account/data/models/models.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';

// Enum for the button's internal state to manage transitions and taps.
enum _ButtonState { idle, goingOnline, goingOffline }

/// A toggle that lets the worker go online/offline.
class GoOnlineButton extends ConsumerStatefulWidget {
  const GoOnlineButton({super.key});

  @override
  ConsumerState<GoOnlineButton> createState() => _GoOnlineButtonState();
}

class _GoOnlineButtonState extends ConsumerState<GoOnlineButton> {
  _ButtonState _buttonState = _ButtonState.idle;

  // Constants for the button's animated geometry
  static const double _pillHeight = 50.0;
  static const double _pillWidth = 160.0;
  static const double _circleDiameter = 50.0;

  Future<void> _handleGoOnline() async {
    if (_buttonState != _ButtonState.idle) return;
    setState(() => _buttonState = _ButtonState.goingOnline);

    // Capture context before async gap
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final BuildContext capturedContext = context;
    final appLocalizations = AppLocalizations.of(capturedContext);

    final cfg = PoofWorkerFlavorConfig.instance;

    // TEST MODE
    if (cfg.testMode) {
      try {
        await ref.read(jobsNotifierProvider.notifier).goOnline();
      } catch (e) {
        if (capturedContext.mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
                content: Text(
                    appLocalizations.goOnlineButtonFailedOnline(e.toString()))),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _buttonState = _ButtonState.idle);
        }
      }
      return;
    }

    // PRODUCTION / STAGING
    try {
      final repo = ref.read(workerAccountRepositoryProvider);
      final worker = await repo.getCheckrOutcome();

      final isActive = worker.accountStatus == AccountStatusType.active;
      final isApproved =
          worker.checkrReportOutcome == CheckrReportOutcome.approved;

      if (isActive) {
        await ref.read(jobsNotifierProvider.notifier).goOnline();
      } else if (!isActive && !isApproved) {
        router.goNamed(AppRouteNames.checkrOutcomePage);
      } else {
        if (capturedContext.mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(appLocalizations.goOnlineButtonAccountInactive),
            ),
          );
        }
      }
    } on ApiException catch (e) {
      if (capturedContext.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(userFacingMessage(capturedContext, e))),
        );
      }
    } catch (e) {
      if (capturedContext.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
              content:
                  Text(appLocalizations.loginUnexpectedError(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _buttonState = _ButtonState.idle);
      }
    }
  }

  Future<void> _handleGoOffline() async {
    if (_buttonState != _ButtonState.idle) return;
    setState(() => _buttonState = _ButtonState.goingOffline);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final appLocalizations = AppLocalizations.of(context);
    final BuildContext capturedContext = context;

    try {
      // This is a quick, client-side state change.
      // The `ref.watch` on `isOnline` will handle the UI rebuild.
      await ref.read(jobsNotifierProvider.notifier).goOffline();
    } catch (e) {
      if (capturedContext.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
              content: Text(
                  appLocalizations.goOnlineButtonFailedOffline(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _buttonState = _ButtonState.idle);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isOnline =
        ref.watch(jobsNotifierProvider.select((state) => state.isOnline));
    final appLocalizations = AppLocalizations.of(context);

    // Determine current visual and interaction state
    final bool isLoading = _buttonState == _ButtonState.goingOnline;
    final bool isDisabled = _buttonState != _ButtonState.idle;
    final bool showPill = !isLoading;

    final Color backgroundColor =
        isOnline ? Colors.black54.withValues(alpha: 0.45) : AppColors.poofColor;
    final double targetWidth = showPill ? _pillWidth : _circleDiameter;
    final BorderRadius targetBorderRadius =
        BorderRadius.circular(showPill ? 32.0 : _circleDiameter / 2);
    final VoidCallback? onTap =
        isDisabled ? null : (isOnline ? _handleGoOffline : _handleGoOnline);

    Widget content;
    if (isLoading) {
      content = const SizedBox(
        key: ValueKey('loader'),
        width: _circleDiameter - 24, // Smaller to fit inside circle
        height: _circleDiameter - 24,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
      );
    } else {
      final text = isOnline
          ? appLocalizations.goOnlineButtonGoOffline
          : appLocalizations.goOnlineButtonGoOnline;
      content = Text(text,
          key: ValueKey(text),
          style: TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontWeight: isOnline ? FontWeight.w400 : FontWeight.w600));
    }

    // The AnimatedContainer is what performs the "shrinking" animation by changing its width.
    Widget button = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        width: targetWidth,
        height: _pillHeight,
        duration: const Duration(milliseconds: 350),
        curve: Curves
            .fastOutSlowIn, // A standard Material Design motion curve for a polished feel.
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: targetBorderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: content,
          ),
        ),
      ),
    );

    // Apply shimmer only when offline and not busy
    if (!isOnline && !isDisabled) {
      button =
          button.animate(onPlay: (c) => c.repeat(period: 3.seconds)).shimmer(
                duration: 1.5.seconds,
                curve: Curves.linear,
                color: Colors.white.withValues(alpha: 0.3),
              );
    }

    return button;
  }
}
