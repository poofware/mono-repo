import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/providers/app_providers.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/utils/error_utils.dart';
import 'package:poof_worker/core/routing/router.dart';

/// A simple page that displays a "Signing out..." message with
/// a loading spinner. It ensures the user sees this for at least
/// two seconds before redirecting to the welcome screen.
class SigningOutPage extends ConsumerStatefulWidget {
  const SigningOutPage({super.key});

  @override
  ConsumerState<SigningOutPage> createState() => _SigningOutPageState();
}

class _SigningOutPageState extends ConsumerState<SigningOutPage> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_performSignOut);
  }

  Future<void> _performSignOut() async {
    final startTime = DateTime.now();
    
    // Capture context before async gap
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final BuildContext capturedContext = context;

    try {
      // 1) Perform sign-out logic
      final config = PoofWorkerFlavorConfig.instance;
      await ref.read(authControllerProvider).signOut(config.testMode);
    } catch(e) {
      // Even if logout fails, we still want to redirect the user.
      // We can show a quick, non-blocking error message.
      String errorMessage;
      if (e is ApiException) {
        if (!capturedContext.mounted) return;
        errorMessage = userFacingMessage(capturedContext, e);
      } else {
        if (!capturedContext.mounted) return;
        errorMessage = AppLocalizations.of(capturedContext).loginUnexpectedError(e.toString());
      }
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }

    // 2) Ensure at least 1 second on this page for a better user experience
    final elapsed = DateTime.now().difference(startTime);
    const minDuration = Duration(seconds: 1);
    if (elapsed < minDuration) {
      await Future.delayed(minDuration - elapsed);
    }

    // 3) Redirect to welcome page
    if (mounted) {
      setState(() => _done = true);
      router.goNamed(AppRouteNames.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    // Simple UI with a spinner + "Signing out..." text
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: _done
                ? const SizedBox.shrink()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        appLocalizations.signingOutMessage,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
