package dtos

import (
	"time"

	"github.com/google/uuid"
	shared_dtos "github.com/poofware/mono-repo/backend/shared/go-dtos"
	"github.com/poofware/mono-repo/backend/shared/go-models"
)

// AdminCreateJobDefinitionRequest is used by admins to create a job definition for a specific manager.
type AdminCreateJobDefinitionRequest struct {
	ManagerID                  uuid.UUID                 `json:"manager_id" validate:"required"`
	PropertyID                 uuid.UUID                 `json:"property_id" validate:"required"`
	Title                      string                    `json:"title" validate:"required,min=1"`
	Description                *string                   `json:"description,omitempty"`
	AssignedBuildingIDs        []uuid.UUID               `json:"assigned_building_ids" validate:"required,min=1,dive,required"`
	DumpsterIDs                []uuid.UUID               `json:"dumpster_ids" validate:"required,min=1,dive,required"`
	Frequency                  models.JobFrequencyType   `json:"frequency" validate:"required,oneof=DAILY WEEKDAYS WEEKLY BIWEEKLY MONTHLY CUSTOM"`
	Weekdays                   []int16                   `json:"weekdays,omitempty" validate:"omitempty,dive,gte=0,lte=6"`
	IntervalWeeks              *int                      `json:"interval_weeks,omitempty" validate:"omitempty,gt=0"`
	StartDate                  time.Time                 `json:"start_date" validate:"required"`
	EndDate                    *time.Time                `json:"end_date,omitempty" validate:"omitempty,gtfield=StartDate"`
	EarliestStartTime          time.Time                 `json:"earliest_start_time" validate:"required"`
	LatestStartTime            time.Time                 `json:"latest_start_time" validate:"required,gtfield=EarliestStartTime"`
	StartTimeHint              *time.Time                `json:"start_time_hint,omitempty" validate:"omitempty,gtfield=EarliestStartTime,ltfield=LatestStartTime"`
	SkipHolidays               bool                      `json:"skip_holidays"`
	HolidayExceptions          []time.Time               `json:"holiday_exceptions,omitempty" validate:"omitempty,dive,required"`
	Details                    *models.JobDetails        `json:"details,omitempty" validate:"omitempty"`
	Requirements               *models.JobRequirements   `json:"requirements,omitempty" validate:"omitempty"`
	CompletionRules            *models.JobCompletionRules `json:"completion_rules,omitempty" validate:"omitempty"`
	SupportContact             *models.SupportContact    `json:"support_contact,omitempty" validate:"omitempty"`
	DailyPayEstimates          []DailyPayEstimateRequest `json:"daily_pay_estimates,omitempty" validate:"omitempty,dive"`
	GlobalBasePay              *float64                  `json:"global_base_pay,omitempty" validate:"omitempty,gt=0"`
	GlobalEstimatedTimeMinutes *int                      `json:"global_estimated_time_minutes,omitempty" validate:"omitempty,gt=0"`
}

// AdminUpdateJobDefinitionRequest is used by admins to update a job definition.
type AdminUpdateJobDefinitionRequest struct {
	DefinitionID               uuid.UUID                   `json:"definition_id" validate:"required"`
	Title                      *string                     `json:"title,omitempty" validate:"omitempty,min=1"`
	Description                *string                     `json:"description,omitempty"`
	AssignedBuildingIDs        *[]uuid.UUID                `json:"assigned_building_ids,omitempty" validate:"omitempty,min=1,dive,required"`
	DumpsterIDs                *[]uuid.UUID                `json:"dumpster_ids,omitempty" validate:"omitempty,min=1,dive,required"`
	Frequency                  *models.JobFrequencyType    `json:"frequency,omitempty" validate:"omitempty,oneof=DAILY WEEKDAYS WEEKLY BIWEEKLY MONTHLY CUSTOM"`
	Weekdays                   *[]int16                    `json:"weekdays,omitempty" validate:"omitempty,dive,gte=0,lte=6"`
	IntervalWeeks              *int                        `json:"interval_weeks,omitempty" validate:"omitempty,gt=0"`
	StartDate                  *time.Time                  `json:"start_date,omitempty"`
	EndDate                    *time.Time                  `json:"end_date,omitempty"`
	EarliestStartTime          *time.Time                  `json:"earliest_start_time,omitempty"`
	LatestStartTime            *time.Time                  `json:"latest_start_time,omitempty"`
	StartTimeHint              *time.Time                  `json:"start_time_hint,omitempty"`
	SkipHolidays               *bool                       `json:"skip_holidays,omitempty"`
	HolidayExceptions          *[]time.Time                `json:"holiday_exceptions,omitempty" validate:"omitempty,dive,required"`
	Details                    *models.JobDetails          `json:"details,omitempty"`
	Requirements               *models.JobRequirements     `json:"requirements,omitempty"`
	CompletionRules            *models.JobCompletionRules  `json:"completion_rules,omitempty"`
	SupportContact             *models.SupportContact      `json:"support_contact,omitempty"`
	DailyPayEstimates          *[]DailyPayEstimateRequest  `json:"daily_pay_estimates,omitempty" validate:"omitempty,dive"`
	GlobalBasePay              *float64                    `json:"global_base_pay,omitempty" validate:"omitempty,gt=0"`
	GlobalEstimatedTimeMinutes *int                        `json:"global_estimated_time_minutes,omitempty" validate:"omitempty,gt=0"`
}

// AdminDeleteJobDefinitionRequest is used to soft-delete a job definition.
type AdminDeleteJobDefinitionRequest struct {
	DefinitionID uuid.UUID `json:"definition_id" validate:"required"`
}

// AdminConfirmationResponse is a generic success response for admin actions.
type AdminConfirmationResponse struct {
	Message string `json:"message"`
	ID      string `json:"id"`
}

// Use the shared DTO for validation errors.
type ValidationErrorDetail shared_dtos.ValidationErrorDetail