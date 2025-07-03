// app_state_notifier.dart
//Don't need now but at some point will
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_state.dart';

class AppStateNotifier extends StateNotifier<AppStateData> {
  // Initialize with a default state.
  AppStateNotifier() : super(const AppStateData());

  /// Example method to set 'isLoading':
  void setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  /// Example method to set 'isLoggedIn':
  void setLoggedIn(bool isLoggedIn) {
    state = state.copyWith(isLoggedIn: isLoggedIn);
  }
}
