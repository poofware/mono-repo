import 'package:flutter/material.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'home_page.dart';
import 'accepted_jobs_page.dart';
import 'package:poof_worker/features/earnings/presentation/pages/earnings_page.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart'; // Import AppLocalizations

/// A main screen that uses TabBar & TabBarView (with DefaultTabController)
class MainTabsScreen extends StatelessWidget {
  const MainTabsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        resizeToAvoidBottomInset: false, // <-- FIX: Prevents the body from resizing for the keyboard
        // The body is a TabBarView with each of the 3 pages
        body: const TabBarView(
          // Disable the left/right swipe:
          physics: NeverScrollableScrollPhysics(),
          children: [
            HomePage(),
            AcceptedJobsPage(),
            EarningsPage(),
          ],
        ),

        // Make the bottom bar transparent:
        bottomNavigationBar: Material(
          // Keep this transparent if you like
          color: Colors.transparent,

          // Add a Container to give the TabBar extra vertical space
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16), // Increase vertical space
            child: TabBar(
              labelColor: AppColors.buttonBackground,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.transparent,   // no underline
              indicatorWeight: 0,                   // be doubly sure
              indicator: const UnderlineTabIndicator(borderSide: BorderSide.none),
              dividerColor: Colors.transparent,     // ← this is the line you still see
              dividerHeight: 0,                     // (optional) don’t reserve any height
              splashFactory: NoSplash.splashFactory, // Disable the splash effect
              overlayColor: WidgetStateProperty.resolveWith<Color?>(
                (Set<WidgetState> states) {
                  // Returns transparent for all states, effectively removing the overlay
                  return Colors.transparent;
                },
              ),
              tabs: [
                Tab(icon: const Icon(Icons.home), text: appLocalizations.mainTabsHome),
                Tab(icon: const Icon(Icons.work), text: appLocalizations.mainTabsJobs),
                Tab(icon: const Icon(Icons.attach_money), text: appLocalizations.mainTabsEarnings),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
