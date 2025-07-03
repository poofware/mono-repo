import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/state.dart';

final workerStateNotifierProvider =
    StateNotifierProvider<WorkerStateNotifier, WorkerState>(
  (ref) => WorkerStateNotifier(),
);
