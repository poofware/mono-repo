package models

import (
	"time"

	"github.com/google/uuid"
)

// Admin represents an administrative user.
type Admin struct {
	Versioned

	ID           uuid.UUID `json:"id"`
	Username     string    `json:"username"`
	PasswordHash string    `json:"-"` // Never serialize to JSON

	// TOTPSecret is encrypted at rest.
	TOTPSecret string `json:"totp_secret,omitempty"`

	// AccountStatus determines if the user can log in.
	AccountStatus AccountStatusType `json:"account_status"`
	SetupProgress SetupProgressType `json:"setup_progress"`
	CreatedAt     time.Time         `json:"created_at"`
	UpdatedAt     time.Time         `json:"updated_at"`
}

func (a *Admin) GetID() string {
	return a.ID.String()
}