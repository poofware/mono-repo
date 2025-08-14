package repositories

import (
    "context"
    "time"

    "github.com/google/uuid"
    "github.com/poofware/mono-repo/backend/services/auth-service/internal/models"
)

// TokenRepository is the interface used by the JWT service
// and auth services to manage refresh tokens in the DB.
//
// Normal usage (login, refresh, logout) should call `Remove*` methods
// so that tokens are fully deleted from the database.
//
// Admin / security usage may call the `Revoke*` methods, which set
// revoked = TRUE (keeping the row present for audit / compliance).
type TokenRepository interface {
    // Create stores a newly issued refresh token (hashed) in the DB.
    CreateRefreshToken(ctx context.Context, token *models.RefreshToken) error

    // GetRefreshToken fetches a refresh token by its raw token (we hash it internally).
    // Returns nil if not found.
    GetRefreshToken(ctx context.Context, rawToken string) (*models.RefreshToken, error)

    // RemoveRefreshToken DELETEs a single token row (by its UUID) from the DB.
    // For normal usage (logout, refresh rotation).
    RemoveRefreshToken(ctx context.Context, id uuid.UUID) error

    // RemoveAllRefreshTokensByUserID DELETEs all refresh tokens for a given user.
    // For normal usage (e.g. re-login).
    RemoveAllRefreshTokensByUserID(ctx context.Context, userID uuid.UUID) error

    // RevokeRefreshToken sets revoked = TRUE for the given token ID.
    // For administrative usage if you need to keep the row for compliance logs.
    RevokeRefreshToken(ctx context.Context, id uuid.UUID) error

    // RevokeAllRefreshTokensByUserID sets revoked = TRUE for all tokens of a user.
    // For administrative usage if you need to keep the rows for compliance logs.
    RevokeAllRefreshTokensByUserID(ctx context.Context, userID uuid.UUID) error

    // If you do blacklisting (short-lived Access Tokens):
    BlacklistToken(ctx context.Context, tokenID string, expiresAt time.Time) error
    IsTokenBlacklisted(ctx context.Context, tokenID string) (bool, error)
}

