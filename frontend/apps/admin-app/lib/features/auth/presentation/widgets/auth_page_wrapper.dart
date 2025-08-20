// NEW FILE
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

class AuthPageWrapper extends StatelessWidget {
  const AuthPageWrapper({
    super.key,
    required this.child,
    this.footer,
    this.showBackButton = false,
  });

  final Widget child;
  final Widget? footer;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(color: Color(0xFFF6F8FA)),
        child: Stack(
          children: [
            Positioned(
              top: 40,
              left: 40,
              child: showBackButton
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back, size: 30),
                      color: Colors.black.withOpacity(0.7),
                      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                    )
                  : SvgPicture.asset('assets/vectors/POOF_LOGO-LC_BLACK.svg', height: 35),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
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