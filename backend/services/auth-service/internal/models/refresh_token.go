package models

import (
    "time"

    "github.com/google/uuid"
)

// RefreshToken represents a refresh token issued to a user.
type RefreshToken struct {
    ID        uuid.UUID `json:"id"`
    UserID    uuid.UUID `json:"user_id"`
    Token     string    `json:"token"` // stored as hash in DB
    ExpiresAt time.Time `json:"expires_at"`
    CreatedAt time.Time `json:"created_at"`
    Revoked   bool      `json:"revoked"`
    IPAddress string    `json:"ip_address,omitempty"`
    DeviceID  string    `json:"device_id,omitempty"`
}

func (rt *RefreshToken) IsExpired() bool {
    return time.Now().After(rt.ExpiresAt)
}
