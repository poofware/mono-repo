// go-models/worker.go

package models

import (
	"time"

	"github.com/google/uuid"
)

type AccountStatusType string

const (
	AccountStatusIncomplete             AccountStatusType = "INCOMPLETE"
	AccountStatusBackgroundCheckPending AccountStatusType = "BACKGROUND_CHECK_PENDING"
	AccountStatusActive                 AccountStatusType = "ACTIVE"
)

type SetupProgressType string

const (
	SetupProgressAwaitingPersonalInfo   SetupProgressType = "AWAITING_PERSONAL_INFO"
	SetupProgressIDVerify               SetupProgressType = "ID_VERIFY"
	SetupProgressAchPaymentAccountSetup SetupProgressType = "ACH_PAYMENT_ACCOUNT_SETUP"
	SetupProgressBackgroundCheck        SetupProgressType = "BACKGROUND_CHECK"
	SetupProgressDone                   SetupProgressType = "DONE"
)

type ReportOutcomeType string

const (
	ReportOutcomeApproved                           ReportOutcomeType = "APPROVED"
	ReportOutcomeReviewCharges                      ReportOutcomeType = "REVIEW_CHARGES"
	ReportOutcomeReviewCanceledScreenings           ReportOutcomeType = "REVIEW_CANCELED_SCREENINGS"
	ReportOutcomeReviewChargesAndCanceledScreenings ReportOutcomeType = "REVIEW_CHARGES_AND_CANCELED_SCREENINGS"
	ReportOutcomeDisputePending                     ReportOutcomeType = "DISPUTE_PENDING"
	ReportOutcomeSuspended                          ReportOutcomeType = "SUSPENDED"
	ReportOutcomeUnsuspended                        ReportOutcomeType = "UNSUSPENDED"
	ReportOutcomeCanceled                           ReportOutcomeType = "CANCELED"
	ReportOutcomePreAdverseAction                   ReportOutcomeType = "PRE_ADVERSE_ACTION"
	ReportOutcomeDisqualified                       ReportOutcomeType = "DISQUALIFIED"
	ReportOutcomeUnknownStatus                      ReportOutcomeType = "UNKNOWN"
)

type WaitlistReasonType string

const (
	WaitlistReasonGeographic WaitlistReasonType = "GEOGRAPHIC"
	WaitlistReasonCapacity   WaitlistReasonType = "CAPACITY"
)

type Worker struct {
	Versioned

	ID                        uuid.UUID           `json:"id"`
	Email                     string              `json:"email"`
	PhoneNumber               string              `json:"phone_number"`
	TOTPSecret                string              `json:"totp_secret,omitempty"`
	FirstName                 string              `json:"first_name"`
	LastName                  string              `json:"last_name"`
	StreetAddress             string              `json:"street_address"`
	AptSuite                  *string             `json:"apt_suite,omitempty"`
	City                      string              `json:"city"`
	State                     string              `json:"state"`
	ZipCode                   string              `json:"zip_code"`
	VehicleYear               int                 `json:"vehicle_year"`
	VehicleMake               string              `json:"vehicle_make"`
	VehicleModel              string              `json:"vehicle_model"`
	AccountStatus             AccountStatusType   `json:"account_status"`
	SetupProgress             SetupProgressType   `json:"setup_progress"`
	OnWaitlist                bool                `json:"on_waitlist"`
	WaitlistedAt              *time.Time          `json:"waitlisted_at,omitempty"`
	WaitlistReason            *WaitlistReasonType `json:"waitlist_reason,omitempty"`
	StripeConnectAccountID    *string             `json:"stripe_connect_account_id,omitempty"`
	CurrentStripeIdvSessionID *string             `json:"current_stripe_idv_session_id,omitempty"`
	CheckrCandidateID         *string             `json:"checkr_candidate_id,omitempty"`
	CheckrInvitationID        *string             `json:"checkr_invitation_id,omitempty"`
	CheckrReportID            *string             `json:"checkr_report_id,omitempty"`
	CheckrReportOutcome       ReportOutcomeType   `json:"checkr_report_outcome,omitempty"`
	CheckrReportETA           *time.Time          `json:"checkr_report_eta,omitempty"`

	ReliabilityScore int        `json:"reliability_score"`
	IsBanned         bool       `json:"is_banned"`
	SuspendedUntil   *time.Time `json:"suspended_until,omitempty"`

	TenantToken *string `json:"tenant_token,omitempty"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (w *Worker) GetID() string {
	return w.ID.String()
}
