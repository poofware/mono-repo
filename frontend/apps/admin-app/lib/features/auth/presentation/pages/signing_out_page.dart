// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/core/config/flavors.dart';
import 'package:poof_admin/core/providers/app_state_provider.dart';
import 'package:poof_admin/core/providers/auth_controller_provider.dart';
import 'package:poof_admin/features/auth/presentation/widgets/auth_form_card.dart';
import 'package:poof_admin/features/auth/presentation/widgets/auth_page_wrapper.dart';

class SigningOutPage extends ConsumerStatefulWidget {
  const SigningOutPage({super.key});

  @override
  ConsumerState<SigningOutPage> createState() => _SigningOutPageState();
}

class _SigningOutPageState extends ConsumerState<SigningOutPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_performSignOut);
  }

  Future<void> _performSignOut() async {
    final start = DateTime.now();
    final config = PoofAdminFlavorConfig.instance;

    if (!config.testMode) {
      await ref.read(authControllerProvider).signOut();
    } else {
      await Future.delayed(const Duration(milliseconds: 500));
      ref.read(appStateProvider.notifier).setLoggedIn(false);
    }

    final elapsed = DateTime.now().difference(start);
    if (elapsed < const Duration(seconds: 2)) {
      await Future.delayed(const Duration(seconds: 2) - elapsed);
    }

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
          children: [
            Text('Signing Out', style: textTheme.headlineSmall),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
            const SizedBox(height: 32),
            Text('Please wait...', style: textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}