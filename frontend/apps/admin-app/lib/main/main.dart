import 'package:flutter/material.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:poof_admin/core/providers/app_state_provider.dart';
import 'package:poof_admin/core/providers/auth_controller_provider.dart';
import 'package:poof_admin/core/routing/router.dart';
import 'package:poof_admin/core/theme/app_colors.dart';
import 'package:poof_admin/core/theme/app_constants.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  late final GoRouter _router;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _router = createAdminRouter(ref.read(appStateProvider.notifier));
    _boot();
  }

  Future<void> _boot() async {
    await ref.read(authControllerProvider).initSession();
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
          backgroundColor: AppColors.background,
          body: Center(
            child: SvgPicture.asset(
              'assets/vectors/POOF_SYMBOL_COLOR.svg',
              width: 150,
              height: 150,
            ),
          ),
        ),
      );
    }

    return FlavorBanner(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Poof Admin',
        routerConfig: _router,
        themeMode: ThemeMode.light,
        theme: _buildTheme(Brightness.light),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final bool light = brightness == Brightness.light;
    final baseColor = AppColors.primary;
    final neutral = light ? Colors.white : Colors.grey[900]!;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: baseColor,
      brightness: brightness,
    ).copyWith(
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
      textTheme: light
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