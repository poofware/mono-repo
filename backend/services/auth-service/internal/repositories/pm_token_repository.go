// meta-service/services/auth-service/internal/repositories/pm_token_repository.go
package repositories

import (
    "context"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v4"
    "github.com/poofware/auth-service/internal/models"
    "github.com/poofware/go-utils"
    . "github.com/poofware/go-repositories"
)

type PMTokenRepository interface {
    TokenRepository
    DB() DB
    CleanupExpiredRefreshTokens(ctx context.Context) error
}

type pmTokenRepository struct {
    db DB
}

func NewPMTokenRepository(db DB) PMTokenRepository {
    return &pmTokenRepository{db: db}
}

func (r *pmTokenRepository) DB() DB {
    return r.db
}

// ----------------------------
// Create / Get
// ----------------------------

func (r *pmTokenRepository) CreateRefreshToken(ctx context.Context, token *models.RefreshToken) error {
    query := `
        INSERT INTO pm_refresh_tokens (id, pm_id, refresh_token, expires_at, created_at, revoked, ip_address, device_id)
        VALUES ($1, $2, $3, $4, NOW(), $5, $6, $7)
    `
    _, err := r.db.Exec(ctx, query,
        token.ID,
        token.UserID,
        utils.HashToken(token.Token),
        token.ExpiresAt,
        token.Revoked,
        token.IPAddress,
        token.DeviceID,
    )
    return err
}

func (r *pmTokenRepository) GetRefreshToken(ctx context.Context, rawToken string) (*models.RefreshToken, error) {
    hashed := utils.HashToken(rawToken)
    query := `
        SELECT id, pm_id, refresh_token, expires_at, created_at, revoked, ip_address, device_id
        FROM pm_refresh_tokens
        WHERE refresh_token = $1
    `
    row := r.db.QueryRow(ctx, query, hashed)

    var rt models.RefreshToken
    err := row.Scan(
        &rt.ID,
        &rt.UserID,
        &rt.Token,
        &rt.ExpiresAt,
        &rt.CreatedAt,
        &rt.Revoked,
        &rt.IPAddress,
        &rt.DeviceID,
    )
    if err != nil {
        if err == pgx.ErrNoRows {
            return nil, nil
        }
        return nil, err
    }
    return &rt, nil
}

// ----------------------------
// Remove methods (normal usage)
// ----------------------------

func (r *pmTokenRepository) RemoveRefreshToken(ctx context.Context, id uuid.UUID) error {
    query := `DELETE FROM pm_refresh_tokens WHERE id = $1`
    _, err := r.db.Exec(ctx, query, id)
    return err
}

func (r *pmTokenRepository) RemoveAllRefreshTokensByUserID(ctx context.Context, userID uuid.UUID) error {
    query := `DELETE FROM pm_refresh_tokens WHERE pm_id = $1`
    _, err := r.db.Exec(ctx, query, userID)
    return err
}

// ----------------------------
// Revoke methods (admin usage)
// ----------------------------

func (r *pmTokenRepository) RevokeRefreshToken(ctx context.Context, id uuid.UUID) error {
    query := `UPDATE pm_refresh_tokens SET revoked = TRUE WHERE id = $1`
    _, err := r.db.Exec(ctx, query, id)
    return err
}

func (r *pmTokenRepository) RevokeAllRefreshTokensByUserID(ctx context.Context, userID uuid.UUID) error {
    query := `UPDATE pm_refresh_tokens SET revoked = TRUE WHERE pm_id = $1 AND revoked = FALSE`
    _, err := r.db.Exec(ctx, query, userID)
    return err
}

// ----------------------------
// Blacklist / Cleanup
// ----------------------------

func (r *pmTokenRepository) BlacklistToken(ctx context.Context, tokenID string, expiresAt time.Time) error {
    query := `
        INSERT INTO pm_blacklisted_tokens (id, token_id, expires_at, created_at)
        VALUES ($1, $2, $3, NOW())
    `
    _, err := r.db.Exec(ctx, query, uuid.New(), tokenID, expiresAt)
    return err
}

func (r *pmTokenRepository) IsTokenBlacklisted(ctx context.Context, tokenID string) (bool, error) {
    query := `
        SELECT EXISTS (
            SELECT 1 FROM pm_blacklisted_tokens
            WHERE token_id = $1 AND expires_at > NOW()
        )
    `
    var exists bool
    err := r.db.QueryRow(ctx, query, tokenID).Scan(&exists)
    return exists, err
}

func (r *pmTokenRepository) CleanupExpiredRefreshTokens(ctx context.Context) error {
    query := `DELETE FROM pm_refresh_tokens WHERE expires_at < NOW()`
    _, err := r.db.Exec(ctx, query)
    return err
}
