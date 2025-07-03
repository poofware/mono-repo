package models

import (
	"time"

	"github.com/google/uuid"
	"github.com/poofware/go-models"
)

// PayoutStatusType defines the possible states of a worker payout.
type PayoutStatusType string

const (
	PayoutStatusPending    PayoutStatusType = "PENDING"
	PayoutStatusProcessing PayoutStatusType = "PROCESSING"
	PayoutStatusPaid       PayoutStatusType = "PAID"
	PayoutStatusFailed     PayoutStatusType = "FAILED"
)

// WorkerPayout represents a weekly payout to a worker.
type WorkerPayout struct {
	models.Versioned
	ID                uuid.UUID        `json:"id"`
	WorkerID          uuid.UUID        `json:"worker_id"`
	WeekStartDate     time.Time        `json:"week_start_date"` // Always a Monday
	WeekEndDate       time.Time        `json:"week_end_date"`   // Always a Sunday
	AmountCents       int64            `json:"amount_cents"`
	Status            PayoutStatusType `json:"status"`
	StripeTransferID  *string          `json:"stripe_transfer_id,omitempty"`
	StripePayoutID    *string          `json:"stripe_payout_id,omitempty"`
	JobInstanceIDs    []uuid.UUID      `json:"job_instance_ids"`
	LastFailureReason *string          `json:"last_failure_reason,omitempty"`
	RetryCount        int              `json:"retry_count"`
	LastAttemptAt     *time.Time       `json:"last_attempt_at,omitempty"`
	NextAttemptAt     *time.Time       `json:"next_attempt_at,omitempty"`
	CreatedAt         time.Time        `json:"created_at"`
	UpdatedAt         time.Time        `json:"updated_at"`
}

func (p *WorkerPayout) GetID() string {
	return p.ID.String()
}
