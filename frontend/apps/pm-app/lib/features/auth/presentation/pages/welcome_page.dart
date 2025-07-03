import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:poof_pm/core/theme/app_constants.dart';
import 'package:poof_pm/core/theme/app_colors.dart';
import 'package:poof_pm/core/presentation/widgets/welcome_button.dart';

/// A simple welcome/landing screen with buttons to log in or create an account.
/// On real usage, it might appear only if user is not logged in.
class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: AppConstants.kDefaultPadding,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Padding(
                padding: const EdgeInsets.only(bottom: AppConstants.kLargeVerticalSpacing),
                child: SvgPicture.asset(
                  'assets/vectors/POOF_LOGO-LC_BLACK.svg',
                  width: 300,
                  fit: BoxFit.contain,
                ),
              ),

              const Text(
                'Welcome to Poof PM',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.kLargeVerticalSpacing),

              // Login
              WelcomeButton(
                text: 'Log In',
                onPressed: () {
                  context.push('/login');
                },
              ),
              const SizedBox(height: AppConstants.kDefaultVerticalSpacing),

              // Create Account
              GestureDetector(
                onTap: () {
                  context.push('/create_account');
                },
                child: const Text(
                  'Create Account',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.buttonBackground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

