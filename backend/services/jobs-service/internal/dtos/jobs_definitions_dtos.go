package dtos

import (
	"time"

	"github.com/google/uuid"
	"github.com/poofware/go-models"
)

// DailyPayEstimateRequest is used within CreateJobDefinitionRequest
// to specify pay and time for each day of the week.
type DailyPayEstimateRequest struct {
	DayOfWeek            int     `json:"day_of_week" validate:"gte=0,lte=6"` // 0=Sunday, ..., 6=Saturday
	BasePay              float64 `json:"base_pay" validate:"gt=0"`
	EstimatedTimeMinutes int     `json:"estimated_time_minutes" validate:"gt=0"`
}

type CreateJobDefinitionRequest struct {
	PropertyID          uuid.UUID               `json:"property_id" validate:"required"`
	Title               string                  `json:"title" validate:"required,min=1"`
	Description         *string                 `json:"description,omitempty"`
	AssignedBuildingIDs []uuid.UUID             `json:"assigned_building_ids" validate:"required,min=1,dive,required"`
	DumpsterIDs         []uuid.UUID             `json:"dumpster_ids" validate:"required,min=1,dive,required"`
	Status              string                  `json:"status,omitempty" validate:"omitempty,oneof=ACTIVE PAUSED ARCHIVED DELETED"`
	Frequency           models.JobFrequencyType `json:"frequency" validate:"required,oneof=DAILY WEEKDAYS WEEKLY BIWEEKLY MONTHLY CUSTOM"`
	Weekdays            []int16                 `json:"weekdays,omitempty" validate:"omitempty,dive,gte=0,lte=6"` // 0=Sunday to 6=Saturday
	IntervalWeeks       *int                    `json:"interval_weeks,omitempty" validate:"omitempty,gt=0"`
	StartDate           time.Time               `json:"start_date" validate:"required"`
	EndDate             *time.Time              `json:"end_date,omitempty" validate:"omitempty,gtfield=StartDate"`

	EarliestStartTime time.Time  `json:"earliest_start_time" validate:"required"`
	LatestStartTime   time.Time  `json:"latest_start_time" validate:"required,gtfield=EarliestStartTime"`
	StartTimeHint     *time.Time `json:"start_time_hint,omitempty" validate:"omitempty,gtfield=EarliestStartTime,ltfield=LatestStartTime"`

	SkipHolidays      bool                       `json:"skip_holidays"`
	HolidayExceptions []time.Time                `json:"holiday_exceptions,omitempty" validate:"omitempty,dive,required"`
	Details           *models.JobDetails         `json:"details,omitempty" validate:"omitempty"`
	Requirements      *models.JobRequirements    `json:"requirements,omitempty" validate:"omitempty"`
	CompletionRules   *models.JobCompletionRules `json:"completion_rules,omitempty" validate:"omitempty"`
	SupportContact    *models.SupportContact     `json:"support_contact,omitempty" validate:"omitempty"`

	// Option 1: Provide estimates for each day of the week explicitly.
	// If this is provided and valid, it takes precedence.
	DailyPayEstimates []DailyPayEstimateRequest `json:"daily_pay_estimates,omitempty" validate:"omitempty,dive"`

	// Option 2: Provide global estimates that will be applied to all relevant days.
	// Used if DailyPayEstimates is not provided or empty.
	GlobalBasePay             *float64 `json:"global_base_pay,omitempty" validate:"omitempty,gt=0"`
	GlobalEstimatedTimeMinutes *int    `json:"global_estimated_time_minutes,omitempty" validate:"omitempty,gt=0"`
}

type CreateJobDefinitionResponse struct {
	DefinitionID uuid.UUID `json:"definition_id"`
}

type SetDefinitionStatusRequest struct {
	DefinitionID uuid.UUID `json:"definition_id"`
	NewStatus    string    `json:"new_status"` // e.g. "PAUSED", "ARCHIVED", "DELETED"
}
