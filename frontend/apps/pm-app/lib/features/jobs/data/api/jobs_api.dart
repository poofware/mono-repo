import 'dart:convert';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_pm/core/config/config.dart';
import '../models/list_jobs_pm_request.dart';
import '../models/list_jobs_pm_response.dart';

class JobsApi with AuthenticatedApiMixin { // Use the mixin for auth
  @override
  final BaseTokenStorage tokenStorage;
  @override
  final void Function()? onAuthLost;
  @override
  final bool useRealAttestation;

  @override
  String get baseUrl => PoofPMFlavorConfig.instance.apiServiceURL;
  @override
  String get authBaseUrl => PoofPMFlavorConfig.instance.authServiceURL;
  @override
  String get refreshTokenPath => '/pm/refresh_token';

  // NEW: Add missing getters to satisfy AuthenticatedApiMixin contract.
  @override
  String get refreshTokenBaseUrl => authBaseUrl;
  @override
  String get attestationChallengeBaseUrl => authBaseUrl;
  @override
  String get attestationChallengePath => '/challenge'; // Default path

  JobsApi({required this.tokenStorage, this.onAuthLost, this.useRealAttestation = false});

  /// POST /api/v1/manager/properties/jobs
  Future<ListJobsPmResponse> fetchJobsForProperty(ListJobsPmRequest request) async {
    final resp = await sendAuthenticatedRequest(
      method: 'POST',
      path: '/jobs/pm/instances',
      body: request,
      requireAttestation: false,
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    return ListJobsPmResponse.fromJson(decoded);
  }
}