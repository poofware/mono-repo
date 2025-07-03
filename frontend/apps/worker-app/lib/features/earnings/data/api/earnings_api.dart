// lib/features/earnings/data/api/earnings_api.dart

import 'dart:convert';

import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/core/config/flavors.dart';

import '../models/earnings_models.dart';

class EarningsApi with AuthenticatedApiMixin {
  @override
  final BaseTokenStorage tokenStorage;

  @override
  final void Function()? onAuthLost;

  @override
  String get baseUrl => PoofWorkerFlavorConfig.instance.apiServiceURL;

  /// For refreshing tokens. We can share the same auth server path or a dedicated route.
  @override
  String get refreshTokenBaseUrl => PoofWorkerFlavorConfig.instance.authServiceURL;

  @override
  String get refreshTokenPath => '/worker/refresh_token';

  @override
  String get attestationChallengeBaseUrl => PoofWorkerFlavorConfig.instance.authServiceURL;

  @override
  String get attestationChallengePath => '/worker/challenge';

  @override
  final bool useRealAttestation;

  EarningsApi({
    required this.tokenStorage,
    this.onAuthLost,
  }) : useRealAttestation = PoofWorkerFlavorConfig.instance.realDeviceAttestation;

  /// GET /earnings/summary
  Future<EarningsSummary> getEarningsSummary() async {
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/earnings/summary',
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    return EarningsSummary.fromJson(decoded);
  }
}
