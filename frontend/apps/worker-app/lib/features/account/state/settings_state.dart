// lib/core/settings/state/settings_state.dart

import 'package:flutter/material.dart';

/// Immutable data class capturing user settings such as themeMode and notifications.
class SettingsState {
  final bool notificationsEnabled;
  final ThemeMode themeMode;

  const SettingsState({
    this.notificationsEnabled = true,
    this.themeMode = ThemeMode.light,
  });

  SettingsState copyWith({
    bool? notificationsEnabled,
    ThemeMode? themeMode,
  }) {
    return SettingsState(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

