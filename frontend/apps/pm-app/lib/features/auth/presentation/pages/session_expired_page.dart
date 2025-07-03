import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Shown if silent refresh fails mid-session. Explains that the
/// user must sign in again, then automatically redirects after ~2s.
class SessionExpiredPage extends ConsumerStatefulWidget {
  const SessionExpiredPage({super.key});

  @override
  ConsumerState<SessionExpiredPage> createState()
      => _SessionExpiredPageState();
}

class _SessionExpiredPageState extends ConsumerState<SessionExpiredPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => _redirectLater());
  }

  Future<void> _redirectLater() async {
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Expired'),
      ),
      body: const SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_clock, size: 72),
              SizedBox(height: 16),
              Text(
                'Your session has expired.\nRedirecting to sign-in…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
              SizedBox(height: 24),
              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

