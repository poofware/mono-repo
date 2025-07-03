// ./src/models/models.dart

/// Marker interface so we can call `.toJson()` on any typed request
abstract class JsonSerializable {
  Map<String, dynamic> toJson();
}

/// Replaces your raw Map token storage with a typed pair
class TokenPair {
  final String accessToken;
  final String refreshToken;

  TokenPair({
    required this.accessToken,
    required this.refreshToken,
  });
}

/// For /pm/email/valid or /worker/email/valid, etc.
class CheckEmailRequest implements JsonSerializable {
  final String email;

  CheckEmailRequest(this.email);

  @override
  Map<String, dynamic> toJson() => {
        'email': email,
      };
}

/// For /pm/phone/valid or /worker/phone/valid, etc.
class CheckPhoneRequest implements JsonSerializable {
  final String phoneNumber;

  CheckPhoneRequest(this.phoneNumber);

  @override
  Map<String, dynamic> toJson() => {
        'phone_number': phoneNumber,
      };
}

/// For TOTP secret generation: { "secret": "...", "qr_code": "..." }
class TOTPSecretResponse {
  final String secret;

  TOTPSecretResponse({
    required this.secret,
  });

  factory TOTPSecretResponse.fromJson(Map<String, dynamic> json) {
    return TOTPSecretResponse(
      secret: json['secret'] as String,
    );
  }
}

/// Request for refresh or logout endpoints
class RefreshTokenRequest implements JsonSerializable {
  final String? refreshToken;

  RefreshTokenRequest({this.refreshToken});

  @override
  Map<String, dynamic> toJson() => {
        'refresh_token': refreshToken,
      };
}

/// Response from refresh endpoint
class RefreshTokenResponse {
  final String? accessToken;
  final String? refreshToken;

  RefreshTokenResponse({
    this.accessToken,
    this.refreshToken,
  });

  factory RefreshTokenResponse.fromJson(Map<String, dynamic> json) {
    return RefreshTokenResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
    );
  }
}

/// Request for /verify/request_email_code
class EmailCodeRequest implements JsonSerializable {
  final String email;

  EmailCodeRequest(this.email);

  @override
  Map<String, dynamic> toJson() => {
        'email': email,
      };
}

/// Request for /verify/check_email_code
class VerifyEmailCodeRequest implements JsonSerializable {
  final String email;
  final String code;

  VerifyEmailCodeRequest({
    required this.email,
    required this.code,
  });

  @override
  Map<String, dynamic> toJson() => {
        'email': email,
        'code': code,
      };
}

/// Request for /verify/request_sms_code
class SMSCodeRequest implements JsonSerializable {
  final String phoneNumber;

  SMSCodeRequest(this.phoneNumber);

  @override
  Map<String, dynamic> toJson() => {
        'phone_number': phoneNumber,
      };
}

/// Request for /verify/check_sms_code
class VerifySMSCodeRequest implements JsonSerializable {
  final String phoneNumber;
  final String code;

  VerifySMSCodeRequest({
    required this.phoneNumber,
    required this.code,
  });

  @override
  Map<String, dynamic> toJson() => {
        'phone_number': phoneNumber,
        'code': code,
      };
}

/// A base login response with typed [TUser].
class LoginResponseBase<TUser> {
  final TUser user;
  final String? accessToken;
  final String? refreshToken;

  LoginResponseBase({
    required this.user,
    this.accessToken,
    this.refreshToken,
  });
}

// ----------------------------------------------------------------------
// NEW: Attestation Challenge Models
// ----------------------------------------------------------------------

/// Request for `POST /challenge`
class ChallengeRequest implements JsonSerializable {
  final String platform; // 'ios' or 'android'

  ChallengeRequest(this.platform);

  @override
  Map<String, dynamic> toJson() => {'platform': platform};
}

/// Response from `POST /challenge`
class ChallengeResponse {
  final String challengeToken;
  final String challenge;

  ChallengeResponse({required this.challengeToken, required this.challenge});

  factory ChallengeResponse.fromJson(Map<String, dynamic> json) {
    return ChallengeResponse(
      challengeToken: json['challenge_token'] as String,
      challenge: json['challenge'] as String,
    );
  }
}

/// The payload that gets JSON-encoded and sent in the X-Device-Integrity header.
class AttestationPayload implements JsonSerializable {
  // Common
  final String challengeToken;
  // Android
  final String? integrityToken;
  // iOS
  final String? keyId;
  final String? attestation;
  final String? assertion;
  final String? clientData;

  AttestationPayload({
    required this.challengeToken,
    this.integrityToken,
    this.keyId,
    this.attestation,
    this.assertion,
    this.clientData,
  });

  @override
  Map<String, dynamic> toJson() {
    return {
      'challenge_token': challengeToken,
      if (integrityToken != null) 'integrity_token': integrityToken,
      if (keyId != null) 'key_id': keyId,
      if (attestation != null) 'attestation': attestation,
      if (assertion != null) 'assertion': assertion,
      if (clientData != null) 'client_data': clientData,
    };
  }
}

