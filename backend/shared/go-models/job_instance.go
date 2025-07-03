package models

import (
    "time"

    "github.com/google/uuid"
)

type InstanceStatusType string

const (
    InstanceStatusOpen       InstanceStatusType = "OPEN"
    InstanceStatusAssigned   InstanceStatusType = "ASSIGNED"
    InstanceStatusInProgress InstanceStatusType = "IN_PROGRESS"
    InstanceStatusCompleted  InstanceStatusType = "COMPLETED"
    InstanceStatusRetired    InstanceStatusType = "RETIRED"
    InstanceStatusCanceled   InstanceStatusType = "CANCELED"
)

type JobInstance struct {
    Versioned

    ID               uuid.UUID          `json:"id"`
    DefinitionID     uuid.UUID          `json:"definition_id"`
    ServiceDate      time.Time          `json:"service_date"`
    Status           InstanceStatusType `json:"status"`
    AssignedWorkerID *uuid.UUID         `json:"assigned_worker_id,omitempty"`
    EffectivePay     float64            `json:"effective_pay"`

    CheckInAt  *time.Time `json:"check_in_at,omitempty"`
    CheckOutAt *time.Time `json:"check_out_at,omitempty"`

    ExcludedWorkerIDs   []uuid.UUID `json:"excluded_worker_ids,omitempty"`
    AssignUnassignCount int         `json:"assign_unassign_count"`
    FlaggedForReview    bool        `json:"flagged_for_review"`

    CreatedAt time.Time `json:"created_at"`
    UpdatedAt time.Time `json:"updated_at"`
}

func (ji *JobInstance) GetID() string {
    return ji.ID.String()
}

