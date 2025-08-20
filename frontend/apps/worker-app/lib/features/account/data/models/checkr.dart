/// Status values returned by `/checkr/status`.
enum CheckrFlowStatus { incomplete, complete }

CheckrFlowStatus _checkrFlowStatusFromString(String raw) {
  switch (raw.toLowerCase()) {
    case 'complete':
      return CheckrFlowStatus.complete;
    case 'incomplete':
      return CheckrFlowStatus.incomplete;
    default:
      throw ArgumentError('Invalid CheckrFlowStatus: $raw');
  }
}

/// Background‑check outcomes (backend enum `ReportOutcomeType`).
enum CheckrReportOutcome {
  approved,
  reviewCharges,
  reviewCanceledScreenings,
  reviewChargesAndCanceledScreenings,
  disputePending,
  suspended,
  unsuspended,
  canceled,
  preAdverseAction,
  disqualified,
  unknown,
}

CheckrReportOutcome checkrOutcomeFromString(String raw) {
  switch (raw) {
    case 'APPROVED':
      return CheckrReportOutcome.approved;
    case 'REVIEW_CHARGES':
      return CheckrReportOutcome.reviewCharges;
    case 'REVIEW_CANCELED_SCREENINGS':
      return CheckrReportOutcome.reviewCanceledScreenings;
    case 'REVIEW_CHARGES_AND_CANCELED_SCREENINGS':
      return CheckrReportOutcome.reviewChargesAndCanceledScreenings;
    case 'DISPUTE_PENDING':
      return CheckrReportOutcome.disputePending;
    case 'SUSPENDED':
      return CheckrReportOutcome.suspended;
    case 'UNSUSPENDED':
      return CheckrReportOutcome.unsuspended;
    case 'CANCELED':
      return CheckrReportOutcome.canceled;
    case 'PRE_ADVERSE_ACTION':
      return CheckrReportOutcome.preAdverseAction;
    case 'DISQUALIFIED':
      return CheckrReportOutcome.disqualified;
    default:
      return CheckrReportOutcome.unknown;
  }
}

/// ─────────────────────────────────────────────────────────────
/// DTOs
/// ─────────────────────────────────────────────────────────────

class CheckrInvitationResponse {
  final String message;
  final String invitationUrl;

  const CheckrInvitationResponse({
    required this.message,
    required this.invitationUrl,
  });

  factory CheckrInvitationResponse.fromJson(Map<String, dynamic> json) {
    return CheckrInvitationResponse(
      message: json['message'] as String? ?? '',
      invitationUrl: json['invitation_url'] as String,
    );
  }
}

class CheckrStatusResponse {
  final CheckrFlowStatus status;

  const CheckrStatusResponse({required this.status});

  factory CheckrStatusResponse.fromJson(Map<String, dynamic> json) {
    return CheckrStatusResponse(
      status: _checkrFlowStatusFromString(json['status'] as String),
    );
  }
}

class CheckrETAResponse {
  /// Localised ETA timestamp (may be `null` if unknown).
  final DateTime? reportEta;

  const CheckrETAResponse({required this.reportEta});

  factory CheckrETAResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['report_eta'] as String?;
    return CheckrETAResponse(
      reportEta: raw == null ? null : DateTime.parse(raw),
    );
  }
}

// NEW: Session Token for Checkr Embed
class CheckrSessionTokenResponse {
  final String token;
  const CheckrSessionTokenResponse({required this.token});

  factory CheckrSessionTokenResponse.fromJson(Map<String, dynamic> json) {
    return CheckrSessionTokenResponse(
      token: json['token'] as String,
    );
  }
}
