package models

import (
	"time"

	"github.com/google/uuid"
)

// PendingWorkerDeletion represents a pending account deletion request for a worker.
type PendingWorkerDeletion struct {
	Token     string    `db:"token"`
	WorkerID  uuid.UUID `db:"worker_id"`
	ExpiresAt time.Time `db:"expires_at"`
}
