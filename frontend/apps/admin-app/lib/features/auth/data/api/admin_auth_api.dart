// frontend/apps/admin-app/lib/features/auth/data/api/admin_auth_api.dart

import 'dart:convert';
import 'package:poof_admin/core/config/flavors.dart';
import 'package:poof_admin/features/auth/data/models/admin.dart';
import 'package:poof_admin/features/auth/data/models/admin_login_request.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';

class AdminAuthApi extends BaseAuthApi<Admin, AdminLoginRequest, JsonSerializable> {
  @override
  final BaseTokenStorage tokenStorage;
 // @override
//  final void Function()? onAuthLost;
  @override
  final bool useRealAttestation;

  @override
  String get baseUrl => PoofAdminFlavorConfig.instance.gatewayURL; // <-- CHANGE THIS
  @override
  String get refreshTokenPath => '/auth/v1/admin/refresh_token'; // <-- CHANGE THIS
  @override
  String get attestationChallengePath => '/auth/v1/challenge'; // <-- CHANGE THIS

  AdminAuthApi({
    required this.tokenStorage,
   // this.onAuthLost,
    this.useRealAttestation = false,
  });

  @override
  Future<LoginResponseBase<Admin>> login(AdminLoginRequest request) async {
    final resp = await sendPublicRequest(
      method: 'POST',
      path: '/auth/v1/admin/login', // <-- CHANGE THIS
      body: request,
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final adminMap = decoded['admin'] as Map<String, dynamic>;
    final adminUser = Admin.fromJson(adminMap);
    return LoginResponseBase<Admin>(user: adminUser);
  }

  @override
  Future<void> logout(RefreshTokenRequest request) async {
    await sendAuthenticatedRequest(
      method: 'POST',
      path: '/auth/v1/admin/logout', // <-- CHANGE THIS
      body: request,
      attemptRefreshOn401: false,
    );
  }

  // Admin app does not handle registration or these other flows.
  @override
  Future<void> register(JsonSerializable request) =>
      Future.error(UnimplementedError());
  @override
  Future<void> checkEmailValid(CheckEmailRequest request) =>
      Future.error(UnimplementedError());
  @override
  Future<void> checkPhoneValid(CheckPhoneRequest request) =>
      Future.error(UnimplementedError());
  @override
  Future<TOTPSecretResponse> generateTOTPSecret() =>
      Future.error(UnimplementedError());
  @override
  Future<void> requestEmailCode(EmailCodeRequest request) =>
      Future.error(UnimplementedError());
  @override
  Future<void> verifyEmailCode(VerifyEmailCodeRequest request) =>
      Future.error(UnimplementedError());
  @override
  Future<void> requestSMSCode(SMSCodeRequest request) =>
      Future.error(UnimplementedError());
  @override
  Future<void> verifySMSCode(VerifySMSCodeRequest request) =>
      Future.error(UnimplementedError());
}