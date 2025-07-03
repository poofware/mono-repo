package models

import (
	"time"

	"github.com/google/uuid"
)

/*──────────────────────────────────────────────────────────────────────────────
  Primary enums
──────────────────────────────────────────────────────────────────────────────*/
type JobStatusType string

const (
	JobStatusActive   JobStatusType = "ACTIVE"
	JobStatusPaused   JobStatusType = "PAUSED"
	JobStatusArchived JobStatusType = "ARCHIVED"
	JobStatusDeleted  JobStatusType = "DELETED"
)

type JobFrequencyType string

const (
	JobFreqDaily    JobFrequencyType = "DAILY"
	JobFreqWeekdays JobFrequencyType = "WEEKDAYS"
	JobFreqWeekly   JobFrequencyType = "WEEKLY"
	JobFreqBiWeekly JobFrequencyType = "BIWEEKLY"
	JobFreqMonthly  JobFrequencyType = "MONTHLY"
	JobFreqCustom   JobFrequencyType = "CUSTOM"
)

/*──────────────────────────────────────────────────────────────────────────────
  Nested JSON field types
──────────────────────────────────────────────────────────────────────────────*/
type EquipmentType string

const (
	EquipTrashBags EquipmentType = "Trash Bags"
	EquipGloves    EquipmentType = "Gloves"
	EquipDolly     EquipmentType = "Dolly"
	EquipPPE       EquipmentType = "PPE"
)

type VehicleRequirementType string

const (
	VehicleNone       VehicleRequirementType = "None"
	VehicleTruck      VehicleRequirementType = "Truck"
	VehicleLargeTruck VehicleRequirementType = "Large Truck"
)

// PayType is no longer directly used in JobDefinition but might be useful elsewhere.
type PayType string

const (
	PayTypeFlat   PayType = "flat"
	PayTypeHourly PayType = "hourly"
)

/*──────────────────────────────────────────────────────────────────────────────
  JSON-serializable helper structs
──────────────────────────────────────────────────────────────────────────────*/
type JobDetails struct {
	PickupLocation       *string  `json:"pickup_location,omitempty"`
	ContainerDescription *string  `json:"container_description,omitempty"`
	SpecialHandling      *string  `json:"special_handling,omitempty"`
	DumpsterInstructions *string  `json:"dumpster_instructions,omitempty"`
	ReferenceMediaURLs   []string `json:"reference_media_urls,omitempty"`
	SafetyInstructions   *string  `json:"safety_instructions,omitempty"`
}

type JobRequirements struct {
	BackgroundCheckRequired bool                   `json:"background_check_required"`
	TrainingRequired        bool                   `json:"training_required"`
	Equipment               []EquipmentType        `json:"equipment,omitempty"`
	VehicleRequirement      VehicleRequirementType `json:"vehicle_requirement,omitempty"`
	PhysicalRequirements    []string               `json:"physical_requirements,omitempty"`
}

// NEW: DailyPayEstimate stores pay and time specific to a day of the week.
type DailyPayEstimate struct {
	DayOfWeek                   time.Weekday `json:"day_of_week"` // Sunday = 0, ... , Saturday = 6
	BasePay                     float64      `json:"base_pay"`
	InitialBasePay              float64      `json:"initial_base_pay"`
	EstimatedTimeMinutes        int          `json:"estimated_time_minutes"`          // Current estimate, subject to EMA
	InitialEstimatedTimeMinutes int          `json:"initial_estimated_time_minutes"`  // Estimate at creation, for proportional pay
}

type JobCompletionRules struct {
	ProofPhotosRequired         bool `json:"proof_photos_required"`
	GPSCheckinRequired          bool `json:"gps_checkin_required"`
	DigitalConfirmationRequired bool `json:"digital_confirmation_required"`
	RatingsEnabled              bool `json:"ratings_enabled"`
}

type SupportContact struct {
	Email *string `json:"email,omitempty"`
	Phone *string `json:"phone,omitempty"`
}

/*──────────────────────────────────────────────────────────────────────────────
  MAIN MODEL – JobDefinition
──────────────────────────────────────────────────────────────────────────────*/
type JobDefinition struct {
	Versioned

	ID         uuid.UUID `json:"id"`
	ManagerID  uuid.UUID `json:"manager_id"`
	PropertyID uuid.UUID `json:"property_id"`

	Title       string  `json:"title"`
	Description *string `json:"description,omitempty"`

	AssignedBuildingIDs []uuid.UUID `json:"assigned_building_ids"`
	DumpsterIDs         []uuid.UUID `json:"dumpster_ids"`

	Status    JobStatusType    `json:"status"`
	Frequency JobFrequencyType `json:"frequency"`

	Weekdays      []int16 `json:"weekdays,omitempty"` // 0=Sunday .. 6=Saturday, matches time.Weekday
	IntervalWeeks *int    `json:"interval_weeks,omitempty"`

	StartDate time.Time  `json:"start_date"`
	EndDate   *time.Time `json:"end_date"`

	EarliestStartTime time.Time `json:"earliest_start_time"`
	LatestStartTime   time.Time `json:"latest_start_time"`
	StartTimeHint     time.Time `json:"start_time_hint"`

	SkipHolidays      bool        `json:"skip_holidays"`
	HolidayExceptions []time.Time `json:"holiday_exceptions,omitempty"`

	Details         JobDetails         `json:"details,omitempty"`
	Requirements    JobRequirements    `json:"requirements,omitempty"`

	CompletionRules JobCompletionRules `json:"completion_rules,omitempty"`
	SupportContact  SupportContact     `json:"support_contact,omitempty"`

	DailyPayEstimates []DailyPayEstimate `json:"daily_pay_estimates"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (j *JobDefinition) GetID() string {
	return j.ID.String()
}

// Helper to get the DailyPayEstimate for a specific day of the week.
// Returns nil if not found.
func (j *JobDefinition) GetDailyEstimate(dayOfWeek time.Weekday) *DailyPayEstimate {
	for i := range j.DailyPayEstimates {
		if j.DailyPayEstimates[i].DayOfWeek == dayOfWeek {
			return &j.DailyPayEstimates[i]
		}
	}
	return nil
}

