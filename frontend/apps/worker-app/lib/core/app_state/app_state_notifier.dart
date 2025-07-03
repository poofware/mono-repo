// lib/core/app_state/app_state_notifier.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_state.dart';

class AppStateNotifier extends StateNotifier<AppStateData> {
  AppStateNotifier() : super(const AppStateData());

  // ─── read-only helpers ───────────────────────────────────────────────
  bool get isLoggedIn  => state.isLoggedIn;
  bool get isLoading   => state.isLoading;

  // ─── mutators ────────────────────────────────────────────────────────
  void setLoading(bool value)   => state = state.copyWith(isLoading: value);
  void setLoggedIn(bool value)  => state = state.copyWith(isLoggedIn: value);
}

