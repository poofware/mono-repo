// worker-app/lib/main/main.dart

import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:geolocator/geolocator.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

import 'package:poof_worker/core/config/flavors.dart';
import 'package:poof_worker/core/theme/app_colors.dart';
import 'package:poof_worker/core/routing/router.dart';
import 'package:poof_worker/core/providers/app_providers.dart';
import 'package:poof_worker/features/account/providers/providers.dart';
import 'package:poof_worker/features/jobs/providers/jobs_provider.dart';
import 'package:poof_worker/features/earnings/providers/providers.dart';
import 'package:poof_worker/features/jobs/presentation/pages/home_page.dart'
    show kDefaultMapZoom, kSanFranciscoLatLng; // For map defaults
import 'package:poof_worker/features/jobs/utils/job_photo_persistence.dart';
import 'package:poof_worker/features/account/data/models/worker.dart';
import 'package:poof_worker/core/presentation/widgets/global_error_listener.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/presentation/widgets/global_debug_listener.dart';
import 'package:poof_worker/core/utils/fresh_install_manager.dart';
 

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Handle fresh install logic before anything else.
  await FreshInstallManager.handleFreshInstall();

  usePathUrlStrategy();

  try {
    final GoogleMapsFlutterPlatform mapsImplementation =
        GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      await mapsImplementation.initializeWithRenderer(AndroidMapRenderer.latest);
    }
  } on PlatformException catch (e) {
    if (e.code == 'Renderer already initialized') {
      debugPrint('Ignoring "Renderer already initialized" exception on hot restart.');
    } else {
      rethrow;
    }
  }

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});
  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  late final GoRouter _router = createRouter(ref.read(appStateProvider.notifier));
  bool _booting = true;
  bool _bootHasRun = false;

  late VideoPlayerController _welcomeVideoController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _welcomeVideoController = VideoPlayerController.asset(
      'assets/videos/trimmed_loop_white_back.mp4',
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    // This is the hook that connects the library's logger to the app's state provider.
    onAuthLog = (String message) {
      // Use the ref to update the provider's state.
      // We do this in a post-frame callback to avoid updating state during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(snackbarDebugProvider.notifier).update((state) => [...state, message]);
        }
      });
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _refreshDataIfAppropriate();
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _welcomeVideoController.dispose();
    super.dispose();
  }

  /// Refreshes data when the app is resumed.
  Future<void> _refreshDataIfAppropriate() async {
    if (!ref.read(appStateProvider).isLoggedIn) return;
    
    final worker = ref.read(workerStateNotifierProvider).worker;
    if (worker == null || worker.accountStatus != AccountStatusType.active) return;
    
    final jobsNotifier = ref.read(jobsNotifierProvider.notifier);
    final earningsNotifier = ref.read(earningsNotifierProvider.notifier);
    final jobsState = ref.read(jobsNotifierProvider);

    // Avoid duplicate refresh if a fetch is already in-flight
    if (jobsState.isLoadingAcceptedJobs || jobsState.isLoadingOpenJobs) {
      ref.read(appLoggerProvider).d('App resumed, but jobs are already loading. Skipping refresh.');
      return;
    }

    if (jobsState.inProgressJob != null) {
      ref.read(appLoggerProvider).d('App resumed, but job is in progress. Skipping refresh.');
      return;
    }
    
    ref.read(appLoggerProvider).d('App resumed, refreshing data...');

    // Always refresh earnings summary.
    earningsNotifier.fetchEarningsSummary(force: true);
    
    // Only refresh jobs if we have location permission; otherwise skip.
    final perm = await Geolocator.checkPermission();
    final hasLocationPerm =
        perm == LocationPermission.always || perm == LocationPermission.whileInUse;

    if (!hasLocationPerm) {
      ref
          .read(appLoggerProvider)
          .d('Location permission missing at resume; skipping jobs refresh.');
      return;
    }

    // Refresh jobs based on online status.
    if (jobsState.isOnline) {
      jobsNotifier.refreshOnlineJobsIfActive();
    } else {
      // If offline, still refresh the user's accepted jobs.
      jobsNotifier.fetchAllMyJobs();
    }
  }

  Future<void> _initializeWelcomeVideo() async {
    try {
      await _welcomeVideoController.initialize();
      await _welcomeVideoController.setLooping(true);
      await _welcomeVideoController.setVolume(0.0);
      await _welcomeVideoController.play();
    } catch (e, s) {
      debugPrint("MyApp: Failed to initialize welcome video: $e\n$s");
    }
  }

  Future<void> _determineInitialCameraPositionAndPermission() async {
    // Policy-compliant: do not prompt for permission at app launch.
    final logger = ref.read(appLoggerProvider);
    logger.d("MyApp: Determining initial camera without prompting...");

    // Only check current permission; do NOT request here.
    final perm = await Geolocator.checkPermission();
    final permissionGranted =
        perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    ref.read(bootTimePermissionGrantedProvider.notifier).state = permissionGranted;
    logger.d("MyApp: Location permission present at boot: $permissionGranted");

    CameraPosition? initialCamera;
    if (permissionGranted) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 7),
          ),
        );
        initialCamera = CameraPosition(
          target: LatLng(pos.latitude, pos.longitude),
          zoom: kDefaultMapZoom,
        );
        logger.d("MyApp: Initial location fetched: ${initialCamera.target}");
      } catch (e) {
        logger.w(
            "MyApp: Boot-time location fetch failed despite permission: $e. Using default LA.");
        initialCamera = const CameraPosition(
          target: kSanFranciscoLatLng,
          zoom: kDefaultMapZoom,
        );
      }
    } else {
      logger.d("MyApp: No permission at boot. Using default San Francisco.");
      initialCamera = const CameraPosition(
        target: kSanFranciscoLatLng,
        zoom: kDefaultMapZoom,
      );
    }
    ref.read(initialBootCameraPositionProvider.notifier).state = initialCamera;
  }

  Future<void> _preloadMapStyleJson() async {
    try {
      final style = await rootBundle.loadString('assets/jsons/map_style.json');
      ref.read(mapStyleJsonProvider.notifier).state = style;
    } catch (_) {
      // ignore; map can render without style
    }
  }

  Future<void> _boot() async {
    final logger = ref.read(appLoggerProvider);
    try {
      // Initialize the video and then update the global provider.
      await _initializeWelcomeVideo();
      ref.read(welcomeVideoControllerProvider.notifier).state =
          _welcomeVideoController;

      await JobPhotoPersistence.cleanupOrphanedPhotos();

      if (!PoofWorkerFlavorConfig.instance.testMode) {
        await ref.read(authControllerProvider).initSession(_router);
      }

      final inProgressJob = ref.read(jobsNotifierProvider).inProgressJob;
      await Future.wait([
        _determineInitialCameraPositionAndPermission(),
        _preloadMapStyleJson(),
      ]);
      if (inProgressJob != null) {
        _router.goNamed(AppRouteNames.jobInProgressPage, extra: inProgressJob);
      } else {
        await initAppLinks(ref, _router);
      }

      if (!_welcomeVideoController.value.isInitialized) {
        await _welcomeVideoController.initialize().catchError((e, s) {
          debugPrint("MyApp: Ensure video init completes error: $e\n$s");
        });
      }
    } catch (e, s) {
      logger.e('A fatal error occurred during app boot.', error: e, stackTrace: s);
    } finally {
      // This block is GUARANTEED to run, ensuring the splash screen is always removed.
      if (mounted) setState(() => _booting = false);
      FlutterNativeSplash.remove();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_booting && !_bootHasRun) {
      _bootHasRun = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
         _boot();
      });
    }
  
    ref.listen<NetworkStatus>(networkStatusProvider, (previous, next) {
      if (previous == NetworkStatus.offline && next == NetworkStatus.online) {
        _refreshDataIfAppropriate();
      }
    });

    if (_booting) {
      return Container(color: Colors.white);
    }

    final currentLocale = ref.watch(currentLocaleProvider);

    // The nested ProviderScope with override is no longer needed.
    return FlavorBanner(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Poof Worker',
        routerConfig: _router,
        locale: currentLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) {
          final status = ref.watch(networkStatusProvider);
          return GlobalDebugListener(
            child: GlobalErrorListener(
              child: Stack(
                children: [
                  const _GlobalMapWarmUp(),
                  child!,
                  if (status == NetworkStatus.offline)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: Colors.redAccent,
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          AppLocalizations.of(context).myAppOfflineBanner,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
        themeMode: ThemeMode.light,
        theme: _buildTheme(Brightness.light),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final bool light = brightness == Brightness.light;
    const neutral = Colors.white;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      primary: AppColors.primary,
    ).copyWith(
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
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? AppColors.background
          : Colors.grey[900],
      cardColor:
          brightness == Brightness.light ? Colors.white : Colors.grey[850],
      canvasColor: brightness == Brightness.light ? null : Colors.grey[800],
      shadowColor: Colors.black54,
      textTheme: brightness == Brightness.light
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
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      appBarTheme: AppBarTheme(backgroundColor: AppColors.primary),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        insetPadding: const EdgeInsets.all(12.0),
        elevation: 4.0,
        backgroundColor: Colors.grey[800],
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 15,
        ),
        actionTextColor: Colors.cyan.shade300,
      ),
    );
  }
}

class _GlobalMapWarmUp extends ConsumerWidget {
  const _GlobalMapWarmUp();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Platform.isAndroid) {
      // Avoid keeping a second GoogleMap alive on Android; it can cause rendering
      // conflicts/blank maps on some devices. iOS keeps the tiny warm-up.
      return const SizedBox.shrink();
    }
    final mainMapMounted = ref.watch(homeMapMountedProvider);
    if (mainMapMounted) return const SizedBox.shrink();
    final initialCam = ref.watch(initialBootCameraPositionProvider) ??
        const CameraPosition(target: kSanFranciscoLatLng, zoom: kDefaultMapZoom);
    final mapStyle = ref.watch(mapStyleJsonProvider) ?? '';
    return Positioned(
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.01, // ensure platform view actually renders on iOS
          child: RepaintBoundary(
            child: SizedBox(
              width: 120,
              height: 120,
              child: GoogleMap(
              initialCameraPosition: initialCam,
              style: mapStyle.isEmpty ? null : mapStyle,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              zoomControlsEnabled: false,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
