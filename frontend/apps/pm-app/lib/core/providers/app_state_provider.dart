import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poof_pm/core/app_state/app_state.dart';
import 'package:poof_pm/core/app_state/app_state_notifier.dart';

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppStateData>(
  (ref) => AppStateNotifier(),
);

