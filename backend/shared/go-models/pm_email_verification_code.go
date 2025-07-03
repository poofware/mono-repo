package models

import (
    "time"

    "github.com/google/uuid"
)

// PMEmailVerificationCode for pm_email_verification_codes table
type PMEmailVerificationCode struct {
    ID               uuid.UUID
    PMID             *uuid.UUID
    PMEmail          string
    VerificationCode string
    ExpiresAt        time.Time
    Attempts         int
    Verified         bool
    VerifiedAt       *time.Time
    VerifiedBy       *string
    CreatedAt        time.Time
}

