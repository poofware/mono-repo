package constants

import "time"

const (
	WebhookMetadataGeneratedByKey = "generated_by"
	WebhookMetadataAccountTypeKey = "account_type"
	WebhookMetadataPayoutIDKey    = "payout_id"
)

// PayoutFailureReason defines constants for internal or non-SDK Stripe failure reasons.
// We use these to standardize logging, error handling, and recovery logic.
const (
	// -- Internal Service Reasons --

	// Worker/Account related failures
	ReasonWorkerNotFound         = "worker_record_not_found"
	ReasonMissingStripeID        = "worker_missing_stripe_connect_id"
	ReasonAccountPayoutsDisabled = "stripe_account_payouts_disabled"

	// Stripe API call failures (for non-Stripe-error-code scenarios)
	ReasonUnknownStripeAccountError  = "unknown_stripe_error_fetching_account"
	ReasonUnknownStripeTransferError = "unknown_stripe_transfer_error"
	ReasonPayoutInitiationFailed     = "payout_initiation_failed"

	// A payout attempt to a restricted account can fail with this code.
	// This is a valid `failure_code` on a `payout` object.
	StripeFailureCodeAccountRestricted = "account_restricted"
)

// Stripe-Specific Identifiers
const (
	StripeCapabilityTransfers = "transfers"
)

// Email Subjects and Content
const (
	EmailSubjectPayoutFailureActionRequired = "Action Required: Your Poof Payout Has Failed"
	EmailSubjectPayoutFailurePlatformIssue  = "URGENT: Platform Payout Failure for Worker %s"
	FinanceTeamEmail                        = "team@thepoofapp.com"
	FinanceTeamName                         = "Poof Finance Team"
	StripeExpressDashboardURL               = "https://connect.stripe.com/app/express"
)

// Payout Business Logic
const (
	MinimumPayoutAmountCents = 50
	PayPeriodStartHourEST    = 4
	DaysInWeek               = 7
	EarningsSummaryDays      = 56 // 8 weeks
	BusinessTimezone         = "America/New_York"
)

// Payout Job Scheduling and Timeouts
const (
	PayoutAggregationCronSpec       = "0 9 * * 1"  // 09:00 UTC on Mondays
	PayoutProcessingCronSpec        = "0 13 * * 2" // 13:00 UTC on Tuesdays
	ShortPayoutAggregationCronSpec  = "0 5 * * *"  // 05:00 UTC Daily
	ShortPayoutProcessingCronSpec   = "0 6 * * *"  // 06:00 UTC Daily
	PayoutAggregationJobTimeout     = 15 * time.Minute
	PayoutProcessingJobTimeout      = 10 * time.Minute
)

// Payout Recovery Logic
const (
	BalanceRecoveryProcessTimeout = 10 * time.Minute
	BalanceRecoveryInitialDelay   = 5 * time.Second
	BalanceRecoveryInitialBackoff = 10 * time.Second
)
