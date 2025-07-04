// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_admin/features/auth/presentation/widgets/auth_page_wrapper.dart';

class SessionExpiredPage extends ConsumerStatefulWidget {
  const SessionExpiredPage({super.key});

  @override
  ConsumerState<SessionExpiredPage> createState() => _SessionExpiredPageState();
}

class _SessionExpiredPageState extends ConsumerState<SessionExpiredPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => _redirectLater());
  }

  Future<void> _redirectLater() async {
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AuthPageWrapper(
      showBackButton: false,
      child: AuthFormCard(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Session Expired', style: textTheme.headlineSmall),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
            const SizedBox(height: 32),
            Text(
              'Your session has expired. Redirecting to sign-in...',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}