// worker-app/lib/core/providers/welcome_video_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

/// Provider holding the global VideoPlayerController for the WelcomePage.
///
/// It is initialized as null and updated by `MyApp` during the boot process
/// once the video asset is loaded and ready. Widgets can watch this provider
/// and will rebuild when the controller becomes available.
final welcomeVideoControllerProvider =
    StateProvider<VideoPlayerController?>((ref) => null);
