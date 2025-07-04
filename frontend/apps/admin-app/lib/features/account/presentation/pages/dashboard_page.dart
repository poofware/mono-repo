// MODIFIED FILE
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/features/account/presentation/widgets/settings_dialog.dart';

class DashboardPage extends StatelessWidget {
  final Widget child;
  final GoRouterState state;

  const DashboardPage({
    super.key,
    required this.child,
    required this.state,
  });

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
    if (location.startsWith('/dashboard/pms')) {
      return 1;
    }
    // Default to home
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        GoRouter.of(context).go('/dashboard/home');
        break;
      case 1:
        GoRouter.of(context).go('/dashboard/pms');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      appBar: AppBar(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        centerTitle: true,
        title: SvgPicture.asset('assets/vectors/POOF_LOGO-LC_BLACK.svg', height: 30),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 1.0,
        shadowColor: Colors.black.withOpacity(0.1),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) => const SettingsDialog(),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) => _onItemTapped(index, context),
            labelType: NavigationRailLabelType.all,
            destinations: const <NavigationRailDestination>[
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.business_outlined),
                selectedIcon: Icon(Icons.business),
                label: Text('PMs'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // This is the main content.
          Expanded(
            child: child,
          )
        ],
      ),
    );
  }
}