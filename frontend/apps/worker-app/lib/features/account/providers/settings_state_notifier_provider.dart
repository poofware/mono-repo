import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/state.dart';

/// A global provider for user app settings, powered by a StateNotifier.
final settingsStateNotifierProvider =
    StateNotifierProvider<SettingsStateNotifier, SettingsState>(
  (ref) => SettingsStateNotifier(),
);
