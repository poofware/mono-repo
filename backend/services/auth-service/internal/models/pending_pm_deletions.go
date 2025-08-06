package models

import (
	"time"

	"github.com/google/uuid"
)

// PendingPMDeletion represents a pending account deletion request for a property manager.
type PendingPMDeletion struct {
	Token     string    `db:"token"`
	PMID      uuid.UUID `db:"pm_id"`
	ExpiresAt time.Time `db:"expires_at"`
}
