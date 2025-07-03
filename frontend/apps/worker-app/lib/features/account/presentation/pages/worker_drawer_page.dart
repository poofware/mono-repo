// worker-app/lib/features/account/presentation/pages/worker_drawer_page.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';
import 'package:poof_worker/features/account/providers/providers.dart';
import 'help_and_support_page.dart'; // Import the new page

class WorkerSideDrawer extends ConsumerWidget {
  const WorkerSideDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = AppLocalizations.of(context);
    final width = MediaQuery.of(context).size.width * 0.5;

    return SizedBox(
      width: width,
      child: Drawer(
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            _buildDrawerHeader(context, ref),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildDrawerItem(
                    icon: Icons.person_outline,
                    text: appLocalizations.workerDrawerMyProfile,
                    onTap: () {
                      context.pop();
                      context.pushNamed(AppRouteNames.myProfilePage);
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.help_outline,
                    text: appLocalizations.workerDrawerHelpSupport,
                    onTap: () {
                      context.pop(); // Close the drawer first
                      // Show the new page as a full-screen dialog
                      showGeneralDialog(
                        context: context,
                        barrierDismissible: true,
                        barrierLabel: 'Help & Support',
                        transitionDuration: const Duration(milliseconds: 300),
                        pageBuilder: (_, __, ___) => const HelpAndSupportPage(),
                        transitionBuilder: (context, anim1, anim2, child) {
                          return SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 1),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: anim1,
                              curve: Curves.easeOutCubic,
                            )),
                            child: child,
                          );
                        },
                      );
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.settings_outlined,
                    text: appLocalizations.workerDrawerSettings,
                    onTap: () {
                      context.pop();
                      context.pushNamed(AppRouteNames.settingsPage);
                    },
                  ),
                  const Divider(height: 24, indent: 20, endIndent: 20),
                  _buildDrawerItem(
                    icon: Icons.logout,
                    text: appLocalizations.workerDrawerSignOut,
                    onTap: () {
                      context.pop();
                      context.goNamed(AppRouteNames.signingOutPage);
                    },
                  ),
                ],
              ),
            ),
            _buildDrawerFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerHeader(BuildContext context, WidgetRef ref) {
    final worker = ref.watch(workerStateNotifierProvider).worker;
    final fullName = worker != null && worker.firstName.isNotEmpty
        ? '${worker.firstName} ${worker.lastName}'.trim()
        : 'Poof Worker';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 32,
        bottom: 32,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.poofColor, Color(0xFFB87DFF)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start, // Left-align content
        children: [
          SvgPicture.asset(
            'assets/vectors/POOF_SYMBOL_WHITE_TRANS_BACK.svg',
            height: 48,
            width: 48,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          const SizedBox(height: 12),
          Text(
            fullName,
            // textAlign is no longer needed as the Column's alignment handles it
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, size: 26),
      title: Text(text, style: const TextStyle(fontSize: 16)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildDrawerFooter(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 16,
      ),
      child: Text(
        'Version 0.0.000000001 Very Beta',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 12,
        ),
      ),
    );
  }
}

