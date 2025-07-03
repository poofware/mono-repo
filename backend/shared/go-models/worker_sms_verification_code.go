package models

import (
    "time"

    "github.com/google/uuid"
)

// WorkerSMSVerificationCode for worker_sms_verification_codes table
type WorkerSMSVerificationCode struct {
    ID               uuid.UUID
    WorkerID         *uuid.UUID // <-- New, can be NULL in DB
    WorkerPhone      string
    VerificationCode string
    ExpiresAt        time.Time
    Attempts         int
    Verified         bool
    VerifiedAt       *time.Time
    VerifiedBy       *string
    CreatedAt        time.Time
}

