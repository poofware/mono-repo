// meta-service/services/auth-service/internal/repositories/rate_limit_repository.go
package repositories

import (
	"context"
	"time"

	"github.com/jackc/pgx/v4"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
)

// RateLimitRepository provides an atomic way to check and increment rate limit counters.
type RateLimitRepository interface {
	// IncrementAndCheck atomically increments a counter for the given key and checks if it exceeds the limit.
	// It returns true if the request is allowed (count <= limit), and false otherwise.
	IncrementAndCheck(ctx context.Context, key string, limit int, window time.Duration) (bool, error)
	// CleanupExpired removes all counter keys that have expired.
	CleanupExpired(ctx context.Context) error
}

type rateLimitRepository struct {
	db repositories.DB
}

func NewRateLimitRepository(db repositories.DB) RateLimitRepository {
	return &rateLimitRepository{db: db}
}

func (r *rateLimitRepository) IncrementAndCheck(ctx context.Context, key string, limit int, window time.Duration) (bool, error) {
	query := `
        INSERT INTO rate_limit_attempts (key, attempt_count, expires_at)
        VALUES ($1, 1, NOW() + $2::interval)
        ON CONFLICT (key) DO UPDATE
        SET attempt_count = CASE
            WHEN rate_limit_attempts.expires_at < NOW() THEN 1
            ELSE rate_limit_attempts.attempt_count + 1
        END,
        expires_at = CASE
            WHEN rate_limit_attempts.expires_at < NOW() THEN NOW() + $2::interval
            ELSE rate_limit_attempts.expires_at
        END
        RETURNING attempt_count;
    `

	var currentCount int
	err := r.db.QueryRow(ctx, query, key, window).Scan(&currentCount)
	if err != nil && err != pgx.ErrNoRows {
		return false, err
	}

	return currentCount <= limit, nil
}

func (r *rateLimitRepository) CleanupExpired(ctx context.Context) error {
	query := `DELETE FROM rate_limit_attempts WHERE expires_at < NOW()`
	_, err := r.db.Exec(ctx, query)
	return err
}

