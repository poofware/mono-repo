import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

/// A wrapper for authentication pages that provides a consistent gradient
/// background, the app logo, and a centered, responsive layout for its content.
class AuthPageWrapper extends StatelessWidget {
  const AuthPageWrapper({
    super.key,
    required this.child,
    this.footer,
    this.showBackButton = false,
  });

  /// The main content widget, typically a styled card.
  final Widget child;

  /// An optional widget to display below the main content, like a security message.
  final Widget? footer;

  /// If true, shows a back button in the top-left instead of the logo.
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // The gradient background is a stack of two linear gradients to
        // approximate the look of the Stripe login page.
        decoration: const BoxDecoration(
          color: Color(0xFFF6F8FA),
        ),
        child: Stack(
          children: [
            // Top-left widget: either a back button for navigation within a flow
            // or the app logo on the main entry page.
            Positioned(
              top: 40,
              left: 40,
              child: showBackButton
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back, size: 30),
                      color: Colors.black.withOpacity(0.7),
                      tooltip: 'Go back',
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          // Fallback if there's no page to pop to
                          context.go('/');
                        }
                      },
                    )
                  : SvgPicture.asset(
                      'assets/vectors/POOF_LOGO-LC_BLACK.svg',
                      height: 35,
                    ),
            ),
            // The main content is centered and scrollable.
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 48.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: child,
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: 32),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: footer,
                      ),
                    ]
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}