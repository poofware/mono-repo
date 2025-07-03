// worker-app/lib/features/account/state/worker_state.dart

import 'package:poof_worker/features/account/data/models/worker.dart';

/// Immutable container for the current Worker data.
/// If [worker] is null, we have not loaded or do not have a Worker.
class WorkerState {
  final Worker? worker;

  const WorkerState({this.worker});

  WorkerState copyWith({Worker? worker}) {
    return WorkerState(
      worker: worker ?? this.worker,
    );
  }
}

