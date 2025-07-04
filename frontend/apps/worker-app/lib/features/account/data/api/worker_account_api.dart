// lib/features/account/data/api/worker_account_api.dart

import 'dart:convert';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/config/flavors.dart';

import '../models/models.dart';

/// Worker‑specific account API that transparently refreshes tokens
/// (via [AuthenticatedApiMixin]) and can trigger global logout if refresh fails.
class WorkerAccountApi with AuthenticatedApiMixin {
  @override
  final BaseTokenStorage tokenStorage;

  @override
  String get baseUrl => PoofWorkerFlavorConfig.instance.apiServiceURL;

  /// For refreshing tokens. We can share the same auth server path or a dedicated route.
  @override
  String get refreshTokenBaseUrl =>
      PoofWorkerFlavorConfig.instance.authServiceURL;

  @override
  String get refreshTokenPath => '/worker/refresh_token';

  @override
  String get attestationChallengeBaseUrl =>
      PoofWorkerFlavorConfig.instance.authServiceURL;

  @override
  String get attestationChallengePath => '/worker/challenge';

  @override
  final bool useRealAttestation;

  /// Optional callback if refresh fails and we lose auth.
  @override
  final void Function()? onAuthLost;

  WorkerAccountApi({
    required this.tokenStorage,
    this.onAuthLost,
  }) : useRealAttestation =
            PoofWorkerFlavorConfig.instance.realDeviceAttestation; //

  // ------------------------------------------------------------------
  // Worker record
  // ------------------------------------------------------------------
  Future<Worker> getWorker() async {
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/account/worker',
    );
    return Worker.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Patch (update) the worker record. Returns the updated Worker object.
  Future<Worker> patchWorker(WorkerPatchRequest patch) async {
    final resp = await sendAuthenticatedRequest(
      method: 'PATCH',
      path: '/account/worker',
      body: patch, // Patch request implements JsonSerializable
    );
    return Worker.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// POST /account/worker/personal-info
  /// Submits the worker's personal and vehicle information.
  Future<Worker> submitPersonalInfo(SubmitPersonalInfoRequest request) async {
    final resp = await sendAuthenticatedRequest(
      method: 'POST',
      path: '/account/worker/personal-info',
      body: request,
    ); //
    return Worker.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ------------------------------------------------------------------
  // Checkr background‑check
  // ------------------------------------------------------------------
  Future<CheckrInvitationResponse> createCheckrInvitation() async {
    final resp = await sendAuthenticatedRequest(
      method: 'POST',
      path: '/account/worker/checkr/invitation',
    );
    return CheckrInvitationResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<CheckrStatusResponse> getCheckrStatus() async {
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/account/worker/checkr/status',
    );
    return CheckrStatusResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<CheckrETAResponse> getCheckrReportEta(String timeZone) async {
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/account/worker/checkr/report-eta?time_zone=$timeZone',
    );
    return CheckrETAResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<CheckrOutcomeResponse> getCheckrOutcome() async {
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/account/worker/checkr/outcome',
    );
    return CheckrOutcomeResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  Future<String> completeBackgroundCheck() async {
    final resp = await sendAuthenticatedRequest(
      method: 'POST',
      path: '/account/worker/checkr/complete',
    );
    return (jsonDecode(resp.body) as Map<String, dynamic>)['message'] as String;
  }

  // NEW: Session Token for Checkr Embed
  Future<CheckrSessionTokenResponse> getCheckrSessionToken() async {
    final resp = await sendAuthenticatedRequest(
      method: 'POST',
      path: '/account/worker/checkr/session-token',
    );
    return CheckrSessionTokenResponse.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  // ------------------------------------------------------------------
  // Stripe Connect / IDV
  // ------------------------------------------------------------------
  Future<String> getStripeConnectFlowUrl() async {
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/account/worker/stripe/connect-flow',
    );
    return (jsonDecode(resp.body) as Map<String, dynamic>)['connect_flow_url']
        as String;
  }

  Future<String> getStripeConnectFlowStatus() async {
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/account/worker/stripe/connect-flow-status',
    );
    return (jsonDecode(resp.body) as Map<String, dynamic>)['status']
        as String;
  }

  Future<String> getStripeIdentityFlowUrl() async {
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/account/worker/stripe/identity-flow',
    );
    return (jsonDecode(resp.body) as Map<String, dynamic>)['identity_flow_url']
        as String;
  }

  Future<String> getStripeIdentityFlowStatus() async {
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/account/worker/stripe/identity-flow-status',
    );
    return (jsonDecode(resp.body) as Map<String, dynamic>)['status'] as String;
  }

  Future<String> getStripeExpressLoginLink() async {
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/account/worker/stripe/express-login-link',
    );
    return (jsonDecode(resp.body) as Map<String, dynamic>)['login_link_url']
        as String;
  }
}
