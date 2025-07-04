// app_state_notifier.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_state.dart';

class AppStateNotifier extends StateNotifier<AppStateData> {
  // Initialize with a default state.
  AppStateNotifier() : super(const AppStateData());

  // Add these getters to expose the state's properties directly.
  bool get isLoggedIn => state.isLoggedIn;
  bool get isLoading => state.isLoading;

  /// Example method to set 'isLoading':
  void setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  /// Example method to set 'isLoggedIn':
  void setLoggedIn(bool isLoggedIn) {
    state = state.copyWith(isLoggedIn: isLoggedIn);
  }
}