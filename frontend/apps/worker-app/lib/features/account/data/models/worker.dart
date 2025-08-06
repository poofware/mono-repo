// lib/features/account/data/models/worker.dart

import 'package:poof_flutter_auth/poof_flutter_auth.dart';
import 'checkr.dart';

/// ---------------------------------------------------------------------------
/// Enums mirroring backend strings
/// ---------------------------------------------------------------------------
enum AccountStatusType { incomplete, backgroundCheckPending, active }

enum SetupProgressType {
  awaitingPersonalInfo,
  idVerify,
  achPaymentAccountSetup,
  backgroundCheck,
  done,
}

enum WaitlistReason { geographic, capacity, none }

/// ---------------------------------------------------------------------------
/// Worker model (matches backend DTO)
/// ---------------------------------------------------------------------------
class Worker {
  /// NEW: backend UUID returned as a string
  final String id;

  final String email;
  final String phoneNumber;
  final String firstName;
  final String lastName;
  final String streetAddress;
  final String? aptSuite;
  final String city;
  final String state;
  final String zipCode;
  final int vehicleYear;
  final String vehicleMake;
  final String vehicleModel;
  final String? checkrCandidateId;

  // Enum fields
  final AccountStatusType accountStatus;
  final SetupProgressType setupProgress;

  // Checkr status info
  final CheckrReportOutcome checkrReportOutcome;
  final bool onWaitlist;
  final WaitlistReason waitlistReason;

  const Worker({
    required this.id,
    required this.email,
    required this.phoneNumber,
    required this.firstName,
    required this.lastName,
    required this.streetAddress,
    this.aptSuite,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.vehicleYear,
    required this.vehicleMake,
    required this.vehicleModel,
    this.checkrCandidateId,
    required this.accountStatus,
    required this.setupProgress,
    required this.checkrReportOutcome,
    required this.onWaitlist,
    required this.waitlistReason,
  });

  // -------------------------------------------------------------------------
  // Factory helpers for enum decoding
  // -------------------------------------------------------------------------
  static AccountStatusType _accountStatusFrom(String raw) {
    switch (raw) {
      case 'INCOMPLETE':
        return AccountStatusType.incomplete;
      case 'BACKGROUND_CHECK_PENDING':
        return AccountStatusType.backgroundCheckPending;
      case 'ACTIVE':
        return AccountStatusType.active;
      default:
        throw ArgumentError('Unknown AccountStatusType: $raw');
    }
  }

  static SetupProgressType _setupProgressFrom(String raw) {
    switch (raw) {
      case 'AWAITING_PERSONAL_INFO':
        return SetupProgressType.awaitingPersonalInfo;
      case 'ID_VERIFY':
        return SetupProgressType.idVerify;
      case 'ACH_PAYMENT_ACCOUNT_SETUP':
        return SetupProgressType.achPaymentAccountSetup;
      case 'BACKGROUND_CHECK':
        return SetupProgressType.backgroundCheck;
      case 'DONE':
        return SetupProgressType.done;
      default:
        throw ArgumentError('Unknown SetupProgressType: $raw');
    }
  }

  static WaitlistReason _waitlistReasonFrom(String? raw) {
    switch (raw) {
      case 'GEOGRAPHIC':
        return WaitlistReason.geographic;
      case 'CAPACITY':
        return WaitlistReason.capacity;
      default:
        return WaitlistReason.none;
    }
  }

  // -------------------------------------------------------------------------
  // JSON factory
  // -------------------------------------------------------------------------
  factory Worker.fromJson(Map<String, dynamic> json) {
    return Worker(
      id: json['id'] as String, // <-- NEW
      email: json['email'] as String,
      phoneNumber: json['phone_number'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      streetAddress: json['street_address'] as String,
      aptSuite: json['apt_suite'] as String?,
      city: json['city'] as String,
      state: json['state'] as String,
      zipCode: json['zip_code'] as String,
      vehicleYear: json['vehicle_year'] as int,
      vehicleMake: json['vehicle_make'] as String,
      vehicleModel: json['vehicle_model'] as String,
      checkrCandidateId: json['checkr_candidate_id'] as String?,
      accountStatus: _accountStatusFrom(json['account_status'] as String),
      setupProgress: _setupProgressFrom(json['setup_progress'] as String),
      checkrReportOutcome: checkrOutcomeFromString(
        json['checkr_report_outcome'] as String,
      ),
      onWaitlist: json['on_waitlist'] as bool,
      waitlistReason: _waitlistReasonFrom(json['waitlist_reason'] as String?),
    );
  }
}

/// Represents a patch (partial update) to a worker's profile.
/// Only non-null fields will be sent to the server.
///
/// Now implements [JsonSerializable], so it can be used
/// directly with [sendAuthenticatedRequest].
class WorkerPatchRequest implements JsonSerializable {
  final String? email;
  final String? phoneNumber;
  final String? firstName;
  final String? lastName;
  final String? streetAddress;
  final String? aptSuite;
  final String? city;
  final String? state;
  final String? zipCode;
  final int? vehicleYear;
  final String? vehicleMake;
  final String? vehicleModel;

  const WorkerPatchRequest({
    this.email,
    this.phoneNumber,
    this.firstName,
    this.lastName,
    this.streetAddress,
    this.aptSuite,
    this.city,
    this.state,
    this.zipCode,
    this.vehicleYear,
    this.vehicleMake,
    this.vehicleModel,
  });

  /// Converts this object to JSON, omitting null fields.
  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (email != null) data['email'] = email;
    if (phoneNumber != null) data['phone_number'] = phoneNumber;
    if (firstName != null) data['first_name'] = firstName;
    if (lastName != null) data['last_name'] = lastName;
    if (streetAddress != null) data['street_address'] = streetAddress;
    if (aptSuite != null) data['apt_suite'] = aptSuite;
    if (city != null) data['city'] = city;
    if (state != null) data['state'] = state;
    if (zipCode != null) data['zip_code'] = zipCode;
    if (vehicleYear != null) data['vehicle_year'] = vehicleYear;
    if (vehicleMake != null) data['vehicle_make'] = vehicleMake;
    if (vehicleModel != null) data['vehicle_model'] = vehicleModel;
    return data;
  }
}

/// Request model for submitting personal and vehicle information during onboarding.
class SubmitPersonalInfoRequest implements JsonSerializable {
  final String streetAddress;
  final String? aptSuite;
  final String city;
  final String state;
  final String zipCode;
  final int vehicleYear;
  final String vehicleMake;
  final String vehicleModel;

  const SubmitPersonalInfoRequest({
    required this.streetAddress,
    this.aptSuite,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.vehicleYear,
    required this.vehicleMake,
    required this.vehicleModel,
  });

  @override
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'street_address': streetAddress,
      'city': city,
      'state': state,
      'zip_code': zipCode,
      'vehicle_year': vehicleYear,
      'vehicle_make': vehicleMake,
      'vehicle_model': vehicleModel,
    };
    if (aptSuite != null && aptSuite!.isNotEmpty) {
      data['apt_suite'] = aptSuite;
    }
    return data;
  }
}
