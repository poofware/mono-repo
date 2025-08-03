package models

import (
	"time"

	"github.com/google/uuid"
)

// UnitVerificationStatus mirrors the unit_verification_status ENUM.
type UnitVerificationStatus string

const (
	UnitVerificationPending  UnitVerificationStatus = "PENDING"
	UnitVerificationVerified UnitVerificationStatus = "VERIFIED"
	UnitVerificationDumped   UnitVerificationStatus = "DUMPED"
	UnitVerificationFailed   UnitVerificationStatus = "FAILED"
)

// AssignedUnitGroup represents a building with its assigned unit IDs.
type AssignedUnitGroup struct {
	BuildingID uuid.UUID   `json:"building_id"`
	UnitIDs    []uuid.UUID `json:"unit_ids"`
	Floors     []int16     `json:"floors"`
}

// JobUnitVerification records the verification status for a single unit within a job instance.
type JobUnitVerification struct {
	Versioned

	ID                   uuid.UUID              `json:"id"`
	JobInstanceID        uuid.UUID              `json:"job_instance_id"`
	UnitID               uuid.UUID              `json:"unit_id"`
	Status               UnitVerificationStatus `json:"status"`
	AttemptCount         int16                  `json:"attempt_count"`
	FailureReasons       []string               `json:"failure_reasons,omitempty"`
	FailureReasonHistory []string               `json:"failure_reason_history,omitempty"`
	PermanentFailure     bool                   `json:"permanent_failure"`
	MissingTrashCan      bool                   `json:"missing_trash_can"`
	CreatedAt            time.Time              `json:"created_at"`
	UpdatedAt            time.Time              `json:"updated_at"`
}

func (j *JobUnitVerification) GetID() string {
	return j.ID.String()
}
