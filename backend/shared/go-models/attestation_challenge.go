// go-models/attestation_challenge.go
// NEW FILE
package models

import (
	"time"

	"github.com/google/uuid"
)

// AttestationChallenge represents a single-use challenge stored in the database.
type AttestationChallenge struct {
	ID           uuid.UUID `json:"id"`
	RawChallenge []byte    `json:"raw_challenge"`
	Platform     string    `json:"platform"`
	ExpiresAt    time.Time `json:"expires_at"`
}
