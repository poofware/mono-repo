package models

import (
    "time"

    "github.com/google/uuid"
)

// WorkerEmailVerificationCode for worker_email_verification_codes table
type WorkerEmailVerificationCode struct {
    ID               uuid.UUID
    WorkerID         *uuid.UUID // <-- New, can be NULL in DB
    WorkerEmail      string
    VerificationCode string
    ExpiresAt        time.Time
    Attempts         int
    Verified         bool
    VerifiedAt       *time.Time
    VerifiedBy       *string
    CreatedAt        time.Time
}

