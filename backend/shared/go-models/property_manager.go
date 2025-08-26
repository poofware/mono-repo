package models

import (
	"time"

	"github.com/google/uuid"
)

type PMAccountStatusType string

const (
	PMAccountStatusIncomplete PMAccountStatusType = "INCOMPLETE"
	PMAccountStatusActive     PMAccountStatusType = "ACTIVE"
)

// PM-specific setup progress aliases for clarity in PM contexts
const (
	PMSetupProgressAwaitingInfo SetupProgressType = "AWAITING_INFO"
	PMSetupProgressDone                 SetupProgressType = "DONE"
)

type PropertyManager struct {
	Versioned

	ID              uuid.UUID           `json:"id"`
	Email           string              `json:"email"`
	PhoneNumber     *string             `json:"phone_number,omitempty"`
	TOTPSecret      string              `json:"totp_secret,omitempty"`
	BusinessName    string              `json:"business_name"`
	BusinessAddress string              `json:"business_address"`
	City            string              `json:"city"`
	State           string              `json:"state"`
	ZipCode         string              `json:"zip_code"`
	AccountStatus   PMAccountStatusType `json:"account_status"`
	SetupProgress   SetupProgressType   `json:"setup_progress"`
	CreatedAt       time.Time           `json:"created_at"`
	UpdatedAt       time.Time           `json:"updated_at"`
	DeletedAt       *time.Time          `json:"deleted_at,omitempty"`
}

// ----- concurrency helpers -----
func (pm *PropertyManager) GetID() string { return pm.ID.String() }
