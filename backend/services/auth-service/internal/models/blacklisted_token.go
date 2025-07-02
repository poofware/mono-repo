package models

import (
    "time"

    "github.com/google/uuid"
)

// BlacklistedToken represents a revoked or invalidated access token
type BlacklistedToken struct {
    ID        uuid.UUID `json:"id"`
    TokenID   string    `json:"token_id"`   // JTI (JWT ID) claim from the token
    ExpiresAt time.Time `json:"expires_at"` // Token expiration time
    CreatedAt time.Time `json:"created_at"` // Time when token was blacklisted
}
