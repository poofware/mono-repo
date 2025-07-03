import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poof_pm/core/theme/app_constants.dart';
import 'package:poof_pm/core/config/flavors.dart';
import 'package:poof_pm/features/auth/providers/pm_auth_providers.dart';
import 'package:poof_pm/core/providers/app_logger_provider.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart' show ApiException;
import '../../data/models/pm_login_request.dart';

/// A simple login page where user enters their email + TOTP code 
/// for TOTP-based login. 
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _totpController  = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    final email    = _emailController.text.trim();
    final totpCode = _totpController.text.trim();

    if (email.isEmpty || totpCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both email and TOTP code.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final logger     = ref.read(appLoggerProvider);
    final pmAuthRepo = ref.read(pmAuthRepositoryProvider);
    final config     = PoofPMFlavorConfig.instance;

    try {
      if (!config.testMode) {
        // Real login
        final creds = PmLoginRequest(email: email, totpCode: totpCode);
        await pmAuthRepo.doLogin(creds);
      } else {
        // Test mode => skip real call
        logger.d('[TEST MODE] Skipping real login call.');
        await Future.delayed(const Duration(seconds: 1));
      }

      if (!mounted) return;
      // If successful:
      context.go('/main');

    } on ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: ${e.message}')),
      );
    } catch (e, st) {
      logger.e('LoginPage: $e\n$st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _totpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // In larger web apps, you might center a container in the viewport
      body: SafeArea(
        child: Padding(
          padding: AppConstants.kDefaultPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              const SizedBox(height: AppConstants.kLargeVerticalSpacing),

              const Text(
                'Log In',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),
              TextField(
                controller: _totpController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'TOTP Code',
                  border: OutlineInputBorder(),
                ),
              ),

              const Spacer(),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                ElevatedButton(
                  onPressed: _handleLogin,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: const Text('Sign In'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

