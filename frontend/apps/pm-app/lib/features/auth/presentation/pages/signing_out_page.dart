import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/core/providers/app_providers.dart';

/// A simple "Signing Out..." page that shows a spinner
/// for ~2 seconds, then redirects to the welcome screen.
/// In real usage, you'd call your pmAuthRepository.signOut().
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
    final start = DateTime.now();

    final config = PoofPMFlavorConfig.instance;
    // If testMode is false => real sign out
    if (!config.testMode) {
      await ref.read(authControllerProvider).signOut();
    } else {
      // Test mode => skip real calls, do a short wait
      await Future.delayed(const Duration(milliseconds: 500));
      // Then just set loggedIn = false
      ref.read(appStateProvider.notifier).setLoggedIn(false);
    }

    // Ensure at least 2 seconds for UI
    final elapsed = DateTime.now().difference(start);
    if (elapsed < const Duration(seconds: 2)) {
      await Future.delayed(const Duration(seconds: 2) - elapsed);
    }

    if (mounted) {
      setState(() => _done = true);
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signing Out'),
      ),
      body: SafeArea(
        child: Center(
          child: _done
              ? const SizedBox.shrink()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Signing out...', style: TextStyle(fontSize: 18)),
                  ],
                ),
        ),
      ),
    );
  }
}

