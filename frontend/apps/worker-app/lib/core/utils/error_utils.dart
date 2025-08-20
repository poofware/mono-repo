// worker-app/lib/core/utils/error_utils.dart
import 'package:flutter/material.dart';
import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'package:poof_worker/l10n/generated/app_localizations.dart';

/// Translates an [ApiException] into a user-friendly, localized string.
///
/// It checks the `errorCode` from the API response and maps it to a
/// localized message from [AppLocalizations]. If a specific error code
/// is not found, it falls back to the `message` property of the exception,
/// and finally to a generic unknown error message.
String userFacingMessage(BuildContext context, ApiException e) {
  final l10n = AppLocalizations.of(context);

  switch (e.errorCode) {
    // --- Specific, common codes ---
    case 'invalid_credentials':
      return l10n.apiErrorInvalidCredentials;
    case 'invalid_totp':
      return l10n.apiErrorInvalidTotp;
    case 'locked_account':
      return l10n.apiErrorLockedAccount;
    case 'conflict':
      return e.message.isNotEmpty ? e.message : l10n.apiErrorConflict;
    case 'phone_not_verified':
      return l10n.apiErrorPhoneNotVerified;
    case 'email_not_verified':
      return l10n.apiErrorEmailNotVerified;
    case 'row_version_conflict':
      return l10n.apiErrorRowVersionConflict;
    case 'location_out_of_bounds':
      return l10n.apiErrorLocationOutOfBounds;
    case 'dump_location_out_of_bounds':
      return l10n.apiErrorDumpLocationOutOfBounds;
    case 'not_within_time_window':
      return l10n.apiErrorNotWithinTimeWindow;
    case 'no_photos_provided':
      return l10n.apiErrorNoPhotosProvided;
    case 'location_inaccurate':
      return l10n.apiErrorLocationInaccurate;

    // --- Generic client/network codes from the auth library ---
    case 'network_offline':
      return l10n.apiErrorNetworkOffline;
    case 'network_timeout':
      return l10n.apiErrorNetworkTimeout;
    case 'network_error':
      return l10n.apiErrorNetworkError;

    // --- Generic server codes ---
    case 'internal_server_error':
      return l10n.apiErrorInternalServerError;
    case 'invalid_payload':
      return l10n.apiErrorInvalidPayload;
    case 'validation_error':
      return l10n.apiErrorValidationError;
    case 'unauthorized':
      return l10n.apiErrorUnauthorized;
    case 'token_expired':
      return l10n.apiErrorTokenExpired;
    case 'not_found':
      return l10n.apiErrorNotFound;

    // --- Fallback to server message or generic unknown error ---
    default:
      return e.message.isNotEmpty ? e.message : l10n.apiErrorUnknown;
  }
}

/// Translates any [Object] error into a user-friendly, localized string.
/// It delegates to [userFacingMessage] for [ApiException] and provides a
/// generic fallback for other exception types.
String userFacingMessageFromObject(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  if (error is ApiException) {
    return userFacingMessage(context, error);
  } else {
    return l10n.loginUnexpectedError(error.toString());
  }
}
