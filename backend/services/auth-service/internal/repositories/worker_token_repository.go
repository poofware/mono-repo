// meta-service/services/auth-service/internal/repositories/worker_token_repository.go
package repositories

import (
    "context"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v4"
    "github.com/poofware/mono-repo/backend/services/auth-service/internal/models"
    "github.com/poofware/mono-repo/backend/shared/go-utils"
    . "github.com/poofware/mono-repo/backend/shared/go-repositories"
)

type WorkerTokenRepository interface {
    TokenRepository
    DB() DB
    CleanupExpiredRefreshTokens(ctx context.Context) error
}

type workerTokenRepository struct {
    db DB
}

func NewWorkerTokenRepository(db DB) WorkerTokenRepository {
    return &workerTokenRepository{db: db}
}

func (r *workerTokenRepository) DB() DB {
    return r.db
}

// ----------------------------
// Create / Get
// ----------------------------

func (r *workerTokenRepository) CreateRefreshToken(ctx context.Context, token *models.RefreshToken) error {
    query := `
        INSERT INTO worker_refresh_tokens (id, worker_id, refresh_token, expires_at, created_at, revoked, ip_address, device_id)
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

func (r *workerTokenRepository) GetRefreshToken(ctx context.Context, rawToken string) (*models.RefreshToken, error) {
    hashed := utils.HashToken(rawToken)
    query := `
        SELECT id, worker_id, refresh_token, expires_at, created_at, revoked, ip_address, device_id
        FROM worker_refresh_tokens
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

func (r *workerTokenRepository) RemoveRefreshToken(ctx context.Context, id uuid.UUID) error {
    query := `DELETE FROM worker_refresh_tokens WHERE id = $1`
    _, err := r.db.Exec(ctx, query, id)
    return err
}

func (r *workerTokenRepository) RemoveAllRefreshTokensByUserID(ctx context.Context, userID uuid.UUID) error {
    query := `DELETE FROM worker_refresh_tokens WHERE worker_id = $1`
    _, err := r.db.Exec(ctx, query, userID)
    return err
}

// ----------------------------
// Revoke methods (admin usage)
// ----------------------------

func (r *workerTokenRepository) RevokeRefreshToken(ctx context.Context, id uuid.UUID) error {
    query := `UPDATE worker_refresh_tokens SET revoked = TRUE WHERE id = $1`
    _, err := r.db.Exec(ctx, query, id)
    return err
}

func (r *workerTokenRepository) RevokeAllRefreshTokensByUserID(ctx context.Context, userID uuid.UUID) error {
    query := `UPDATE worker_refresh_tokens SET revoked = TRUE WHERE worker_id = $1 AND revoked = FALSE`
    _, err := r.db.Exec(ctx, query, userID)
    return err
}

// ----------------------------
// Blacklist / Cleanup
// ----------------------------

func (r *workerTokenRepository) BlacklistToken(ctx context.Context, tokenID string, expiresAt time.Time) error {
    query := `
        INSERT INTO worker_blacklisted_tokens (id, token_id, expires_at, created_at)
        VALUES ($1, $2, $3, NOW())
    `
    _, err := r.db.Exec(ctx, query, uuid.New(), tokenID, expiresAt)
    return err
}

func (r *workerTokenRepository) IsTokenBlacklisted(ctx context.Context, tokenID string) (bool, error) {
    query := `
        SELECT EXISTS (
            SELECT 1 FROM worker_blacklisted_tokens
            WHERE token_id = $1 AND expires_at > NOW()
        )
    `
    var exists bool
    err := r.db.QueryRow(ctx, query, tokenID).Scan(&exists)
    return exists, err
}

func (r *workerTokenRepository) CleanupExpiredRefreshTokens(ctx context.Context) error {
    query := `DELETE FROM worker_refresh_tokens WHERE expires_at < NOW()`
    _, err := r.db.Exec(ctx, query)
    return err
}
