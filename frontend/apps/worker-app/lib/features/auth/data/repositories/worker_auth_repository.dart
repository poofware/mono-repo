import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/features/account/data/models/worker.dart';
import '../models/login_worker_request.dart';
import '../models/register_worker_request.dart';
import 'package:poof_worker/features/account/state/worker_state_notifier.dart';

/// Worker-specific repository.
///
/// Now relies on the **parent** implementation for the shared work
/// (calling the API & saving tokens) and only adds the Worker-state
/// updates – no duplicated code.
class WorkerAuthRepository extends BaseAuthRepository<
    Worker, LoginWorkerRequest, RegisterWorkerRequest> {
  final WorkerStateNotifier _workerNotifier;

  WorkerAuthRepository({
    required super.authApi,
    required super.tokenStorage,
    required WorkerStateNotifier workerNotifier,
  }) : _workerNotifier = workerNotifier;

  @override
  Future<Worker> doLogin(LoginWorkerRequest credentials) async {
    // Delegate common logic to the parent (API call + token save)
    final worker = await super.doLogin(credentials);

    // Then update the global Worker state
    _workerNotifier.setWorker(worker);
    return worker; // keep return type for completeness
  }

  @override
  Future<void> doLogout() async {
    // Run the common token-clearing logic first
    await super.doLogout();

    // Then clear the Worker from memory
    _workerNotifier.clearWorker();
  }
}

