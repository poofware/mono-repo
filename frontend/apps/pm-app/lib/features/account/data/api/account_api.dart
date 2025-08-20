import 'dart:convert';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_pm/core/config/config.dart';
import 'package:poof_pm/features/account/data/models/property_model.dart';

class PropertiesApi with AuthenticatedApiMixin {
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

  PropertiesApi({required this.tokenStorage, this.onAuthLost, this.useRealAttestation = false});

  /// GET /api/v1/account/pm/properties
  Future<List<Property>> fetchProperties() async {
    final resp = await sendAuthenticatedRequest(
      method: 'GET',
      path: '/account/pm/properties', // This should match your backend route
    );
    final decoded = jsonDecode(resp.body) as List<dynamic>;
    return decoded.map((data) => Property.fromJson(data)).toList();
  }
}