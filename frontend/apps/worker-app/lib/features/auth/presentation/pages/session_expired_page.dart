// worker-app/lib/features/auth/presentation/pages/session_expired_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations

/// Shown immediately after silent-refresh failure.
/// Explains what happened, waits ~2 s, clears the flag,
/// then returns the user to the welcome screen.
class SessionExpiredPage extends ConsumerStatefulWidget {
  const SessionExpiredPage({super.key});

  @override
  ConsumerState<SessionExpiredPage> createState() =>
      _SessionExpiredPageState();
}

class _SessionExpiredPageState extends ConsumerState<SessionExpiredPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_redirectLater);
  }

  Future<void> _redirectLater() async {
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) context.goNamed('Home');
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        // THE FIX: The AppBar has been removed.
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_clock, size: 72)
                      .animate()
                      .scale(delay: 200.ms, duration: 400.ms),
                  const SizedBox(height: 24),
                  Text(
                    appLocalizations.sessionExpiredTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appLocalizations.sessionExpiredMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

