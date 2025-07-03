import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_state.dart';

/// A simple global app state. Here, we track whether the user is logged in
/// and whether we're currently showing a loading indicator.
class AppStateNotifier extends StateNotifier<AppStateData> {
  AppStateNotifier() : super(const AppStateData());

  bool get isLoggedIn => state.isLoggedIn;
  bool get isLoading  => state.isLoading;

  void setLoading(bool value) {
    state = state.copyWith(isLoading: value);
  }

  void setLoggedIn(bool value) {
    state = state.copyWith(isLoggedIn: value);
  }
}

