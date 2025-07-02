// meta-service/services/auth-service/internal/repositories/pm_login_attempts_repository.go
package repositories

import (
    "context"
    "time"

    "github.com/google/uuid"
    . "github.com/poofware/go-repositories"
)

type PMLoginAttempts struct {
    PMID        uuid.UUID
    AttemptCount int
    LockedUntil *time.Time
    UpdatedAt   time.Time
    CreatedAt   time.Time
}

type PMLoginAttemptsRepository interface {
    GetOrCreate(ctx context.Context, pmID uuid.UUID) (*PMLoginAttempts, error)
    Increment(ctx context.Context, pmID uuid.UUID, lockDuration, window time.Duration, maxAttempts int) error
    Reset(ctx context.Context, pmID uuid.UUID) error
    IsLocked(ctx context.Context, pmID uuid.UUID) (bool, time.Time, error)
}

type pmLoginAttemptsRepository struct {
    db DB
}

func NewPMLoginAttemptsRepository(db DB) PMLoginAttemptsRepository {
    return &pmLoginAttemptsRepository{db: db}
}

func (r *pmLoginAttemptsRepository) GetOrCreate(ctx context.Context, pmID uuid.UUID) (*PMLoginAttempts, error) {
    query := `
        SELECT pm_id, attempt_count, locked_until, updated_at, created_at
        FROM pm_login_attempts
        WHERE pm_id = $1
    `
    row := r.db.QueryRow(ctx, query, pmID)
    la := &PMLoginAttempts{}
    err := row.Scan(
        &la.PMID,
        &la.AttemptCount,
        &la.LockedUntil,
        &la.UpdatedAt,
        &la.CreatedAt,
    )
    if err == nil {
        return la, nil
    }
    // If no record => insert fresh
    insert := `
        INSERT INTO pm_login_attempts (pm_id, attempt_count, locked_until, updated_at, created_at)
        VALUES ($1, 0, NULL, NOW(), NOW())
        RETURNING pm_id, attempt_count, locked_until, updated_at, created_at
    `
    row = r.db.QueryRow(ctx, insert, pmID)
    err = row.Scan(
        &la.PMID,
        &la.AttemptCount,
        &la.LockedUntil,
        &la.UpdatedAt,
        &la.CreatedAt,
    )
    return la, err
}

func (r *pmLoginAttemptsRepository) Increment(
    ctx context.Context,
    pmID uuid.UUID,
    lockDuration, window time.Duration,
    maxAttempts int,
) error {
    // FIX: Qualify ambiguous columns with 'current.' to prevent SQL error.
    query := `
WITH current AS (
    SELECT pm_id,
           attempt_count,
           locked_until,
           updated_at
    FROM pm_login_attempts
    WHERE pm_id = $1
    FOR UPDATE
)
UPDATE pm_login_attempts
SET attempt_count = CASE
    WHEN (current.locked_until IS NOT NULL AND current.locked_until > NOW())
         THEN current.attempt_count
    ELSE CASE
        WHEN (NOW() - current.updated_at) > $3
            THEN 1
        ELSE current.attempt_count + 1
    END
END,
locked_until = CASE
    WHEN (current.locked_until IS NOT NULL AND current.locked_until > NOW())
         THEN current.locked_until
    ELSE CASE
        WHEN ((NOW() - current.updated_at) <= $3
              AND (current.attempt_count + 1) >= $4)
            THEN NOW() + $2
        ELSE NULL
    END
END,
updated_at = NOW()
FROM current
WHERE pm_login_attempts.pm_id = current.pm_id
RETURNING pm_login_attempts.pm_id
    `
    _, err := r.db.Exec(ctx, query, pmID, lockDuration, window, maxAttempts)
    return err
}

func (r *pmLoginAttemptsRepository) Reset(ctx context.Context, pmID uuid.UUID) error {
    query := `
        UPDATE pm_login_attempts
        SET attempt_count = 0,
            locked_until = NULL,
            updated_at = NOW()
        WHERE pm_id = $1
    `
    _, err := r.db.Exec(ctx, query, pmID)
    return err
}

func (r *pmLoginAttemptsRepository) IsLocked(ctx context.Context, pmID uuid.UUID) (bool, time.Time, error) {
    query := `
        SELECT locked_until
        FROM pm_login_attempts
        WHERE pm_id = $1
    `
    row := r.db.QueryRow(ctx, query, pmID)
    var lockedUntil *time.Time
    if err := row.Scan(&lockedUntil); err != nil {
        return false, time.Time{}, err
    }
    if lockedUntil != nil && lockedUntil.After(time.Now()) {
        return true, *lockedUntil, nil
    }
    return false, time.Time{}, nil
}
