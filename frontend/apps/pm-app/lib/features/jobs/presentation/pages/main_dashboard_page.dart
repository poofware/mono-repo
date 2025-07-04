// lib/features/dashboard/presentation/pages/main_dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_pm/features/jobs/presentation/widgets/settings_dialog.dart';

class MainDashboardPage extends StatelessWidget {
  final Widget child; // This will be the content from GoRouter's ShellRoute
  final GoRouterState state;

  const MainDashboardPage({
    super.key,
    required this.child,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    // Show back button if we are not on the root jobs page
    final bool showBackButton = !state.uri.toString().startsWith('/main/jobs');

    return Scaffold(
      appBar: AppBar(
        // Set a foreground color that contrasts with the background color
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        centerTitle: true,
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/main/jobs');
                  }
                },
              )
            : null,
        automaticallyImplyLeading: false, // We handle the leading widget manually
        title: SvgPicture.asset(
          'assets/vectors/POOF_LOGO-LC_BLACK.svg',
          height: 30,
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 1.0,
        shadowColor: Colors.black.withOpacity(0.1),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              // MODIFICATION: Show a modal dialog instead of navigating to a new page.
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return const SettingsDialog();
                },
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: child, // The actual page content (e.g., PropertiesPage)
    );
  }
}