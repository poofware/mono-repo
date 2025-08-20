import 'package:flutter/material.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:poof_pm/core/providers/app_state_provider.dart';
import 'package:poof_pm/core/theme/app_colors.dart';
import 'package:poof_pm/core/theme/app_constants.dart';
import 'package:poof_pm/core/providers/auth_controller_provider.dart';
import 'package:poof_pm/core/routing/router.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The main entry point for the PM web app (local dev, staging, prod, etc.).
/// Each environment (dev, staging, prod) calls [main()] after configuring a flavor.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

/// Your app's root widget. We now switch from a manual home:Scaffold to a router-based approach,
/// plus call initSession() in _boot() so silent refresh can occur at startup.
class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  /// Our GoRouter, built in [initState].
  late final GoRouter _router;

  /// We hold a short "boot" state while we do initSession + splash
  bool _booting = true;

  @override
  void initState() {
    super.initState();

    // 1) Create the router once, passing the appState for login-checks
    _router = createPmRouter(ref.read(appStateProvider.notifier));

    // 2) Kick off boot tasks (e.g. silent refresh)
    _boot();
  }

  // In lib/main/main.dart, within _MyAppState

Future<void> _boot() async {
  // Attempt silent refresh. If tokens exist, this tries to renew them.
  await ref.read(authControllerProvider).initSession();

  // --- TEMPORARY FOR UI TESTING ---
  // This forces the app into a logged-in state for UI development.
  // REMOVE THIS LINE FOR PRODUCTION or when testing actual auth.
 // ref.read(appStateProvider.notifier).setLoggedIn(true);
  // --- END TEMPORARY ---

  // A short splash (~1 second) so there's a minimal load screen
  await Future.delayed(const Duration(seconds: 1));

  if (mounted) {
    setState(() => _booting = false);
  }
}

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor:
              AppColors.background, // Or your desired splash background
          body: Center(
            child: SvgPicture.asset(
              'assets/vectors/POOF_SYMBOL_COLOR.svg', // ADJUST THIS PATH
              width: 150, // Adjust size
              height: 150, // Adjust size
            ),
          ),
        ),
      );
    }

    // Otherwise, show your real app with the router
    return FlavorBanner(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Poof PM',
        // Our new router-based navigation:
        routerConfig: _router,
    themeMode: ThemeMode.light,
        theme: _buildTheme(Brightness.light),
      ),
    );
  }

  /// Basic Material-3 theme, adapted from your existing code.
  ThemeData _buildTheme(Brightness brightness) {
    final bool light = brightness == Brightness.light;
    final baseColor = AppColors.primary; // or brand color
    final neutral = light ? Colors.white : Colors.grey[900]!;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: baseColor,
      brightness: brightness,
    ).copyWith(
      // Explicitly set the primary color to your exact brand color.
      primary: baseColor,
      surfaceTint: Colors.transparent,
      surface: light ? neutral : Colors.grey[850],
      surfaceContainerLowest: light ? neutral : Colors.grey[900],
      surfaceContainerLow: light ? neutral : Colors.grey[850],
      surfaceContainer: light ? neutral : Colors.grey[850],
      surfaceContainerHigh: light ? neutral : Colors.grey[800],
      surfaceContainerHighest: light ? neutral : Colors.grey[800],
      outline: light ? Colors.black26 : Colors.white24,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      cardColor: light ? Colors.white : Colors.grey[850],
      textTheme:
          light
              ? const TextTheme(
                bodyLarge: TextStyle(color: AppColors.primaryText),
                bodyMedium: TextStyle(color: AppColors.secondaryText),
              )
              : const TextTheme(
                bodyLarge: TextStyle(color: Colors.white),
                bodyMedium: TextStyle(color: Colors.grey),
              ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonBackground,
          foregroundColor: AppColors.buttonText,
          padding: AppConstants.kButtonPadding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}
