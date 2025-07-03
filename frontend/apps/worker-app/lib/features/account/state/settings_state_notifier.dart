// lib/core/settings/state/settings_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'settings_state.dart';

/// A StateNotifier that manages global settings for the app.
/// Using Riverpod's StateNotifier[SettingsState> for reactivity.
class SettingsStateNotifier extends StateNotifier<SettingsState> {
  SettingsStateNotifier() : super(const SettingsState());

  /// Toggle notifications
  void setNotificationsEnabled(bool isEnabled) {
    state = state.copyWith(notificationsEnabled: isEnabled);
  }

  /// Toggle theme mode
  void setThemeMode(bool isDark) {
    state = state.copyWith(
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
    );
  }
}

