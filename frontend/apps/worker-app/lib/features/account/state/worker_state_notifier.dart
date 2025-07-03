// worker-app/lib/features/account/state/worker_state_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'worker_state.dart';
import 'package:poof_worker/features/account/data/models/worker.dart';

/// A Riverpod StateNotifier that holds and updates the current [Worker].
class WorkerStateNotifier extends StateNotifier<WorkerState> {
  WorkerStateNotifier() : super(const WorkerState());

  void setWorker(Worker worker) {
    state = state.copyWith(worker: worker);
  }

  /// Clears out the Worker data (e.g. on logout).
  void clearWorker() {
    state = const WorkerState();
  }

  Worker? get currentWorker => state.worker;
}

