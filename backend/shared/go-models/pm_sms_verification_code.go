package models

import (
    "time"

    "github.com/google/uuid"
)

// PMSMSVerificationCode for pm_sms_verification_codes table
type PMSMSVerificationCode struct {
    ID               uuid.UUID
    PMID             *uuid.UUID // <-- New, can be NULL in DB
    PMPhone          string
    VerificationCode string
    ExpiresAt        time.Time
    Attempts         int
    Verified         bool
    VerifiedAt       *time.Time
    VerifiedBy       *string
    CreatedAt        time.Time
}

