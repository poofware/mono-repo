package dtos

import (
	"time"

	"github.com/google/uuid"
)

// CompletedJobDTO contains simplified details for a completed job instance.
type CompletedJobDTO struct {
	InstanceID      uuid.UUID  `json:"instance_id"`
	PropertyName    string     `json:"property_name"`
	Pay             float64    `json:"pay"`
	CompletedAt     *time.Time `json:"completed_at,omitempty"`
	DurationMinutes *int       `json:"duration_minutes,omitempty"`
}

// DailyEarningDTO represents the total earnings for a single day.
type DailyEarningDTO struct {
	Date        string            `json:"date"`                   // YYYY-MM-DD
	TotalAmount float64           `json:"total_amount"`           // In dollars
	JobCount    int               `json:"job_count"`
	Jobs        []CompletedJobDTO `json:"jobs,omitempty"` // NEW: List of completed jobs
}

// WeeklyEarningsDTO represents a full week's earnings, broken down by day.
type WeeklyEarningsDTO struct {
	WeekStartDate      string            `json:"week_start_date"` // YYYY-MM-DD
	WeekEndDate        string            `json:"week_end_date"`   // YYYY-MM-DD
	WeeklyTotal        float64           `json:"weekly_total"`    // In dollars
	JobCount           int               `json:"job_count"`
	PayoutStatus       string            `json:"payout_status"`   // PENDING, PROCESSING, PAID, FAILED, or CURRENT
	DailyBreakdown     []DailyEarningDTO `json:"daily_breakdown"`
	FailureReason      *string           `json:"failure_reason,omitempty"`
	RequiresUserAction bool              `json:"requires_user_action"`
}

// EarningsSummaryResponse is the top-level response for the earnings summary endpoint.
type EarningsSummaryResponse struct {
	TwoMonthTotal  float64             `json:"two_month_total"`
	CurrentWeek    *WeeklyEarningsDTO  `json:"current_week"`
	PastWeeks      []WeeklyEarningsDTO `json:"past_weeks"`
	NextPayoutDate string              `json:"next_payout_date"`
}
