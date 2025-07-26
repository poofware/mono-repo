// lib/features/account/data/repositories/worker_account_repository.dart

import '../api/worker_account_api.dart';
import '../models/models.dart';
import 'package:poof_worker/features/account/state/worker_state_notifier.dart';

/// Thin repository that exposes all Worker account operations.
/// Additional orchestration / caching logic can be added here later.
class WorkerAccountRepository {
  final WorkerAccountApi _api;
  final WorkerStateNotifier _workerNotifier;

  WorkerAccountRepository(this._api, this._workerNotifier);

  // -------------------- Worker record --------------------
  /// After fetching, update the global WorkerStateNotifier.
  Future<Worker> getWorker() async {
    final w = await _api.getWorker();
    _workerNotifier.setWorker(w);
    return w;
  }

  /// Patch the Worker record. Returns the updated Worker, also updates state.
  Future<Worker> patchWorker(WorkerPatchRequest patchRequest) async {
    final updated = await _api.patchWorker(patchRequest);
    _workerNotifier.setWorker(updated);
    return updated;
  }

  /// Submits personal and vehicle info.
  Future<Worker> submitPersonalInfo(SubmitPersonalInfoRequest request) async {
    final updatedWorker = await _api.submitPersonalInfo(request);
    _workerNotifier.setWorker(updatedWorker);
    return updatedWorker;
  }

  // -------------------- Checkr background‑check --------------------
  Future<CheckrInvitationResponse> createCheckrInvitation() =>
      _api.createCheckrInvitation();

  Future<CheckrStatusResponse> getCheckrStatus() => _api.getCheckrStatus();

  Future<CheckrETAResponse> getCheckrReportEta(String timeZone) =>
      _api.getCheckrReportEta(timeZone);

  Future<Worker> getCheckrOutcome() async {
    final worker = await _api.getCheckrOutcome();
    _workerNotifier.setWorker(worker);
    return worker;
  }

  Future<String> completeBackgroundCheck() => _api.completeBackgroundCheck();

  // NEW: Session Token for Checkr Embed
  Future<CheckrSessionTokenResponse> getCheckrSessionToken() =>
      _api.getCheckrSessionToken();

  // -------------------- Stripe Connect --------------------
  Future<String> getStripeConnectFlowUrl() => _api.getStripeConnectFlowUrl();
  Future<String> getStripeConnectFlowStatus() =>
      _api.getStripeConnectFlowStatus();
  Future<String> getStripeExpressLoginLink() =>
      _api.getStripeExpressLoginLink();

  // -------------------- Stripe Identity Verification --------------------
  Future<String> getStripeIdentityFlowUrl() => _api.getStripeIdentityFlowUrl();
  Future<String> getStripeIdentityFlowStatus() =>
      _api.getStripeIdentityFlowStatus();
}

