// meta-service/services/auth-service/internal/repositories/worker_login_attempts_repository.go
package repositories

import (
    "context"
    "time"

    "github.com/google/uuid"
    . "github.com/poofware/go-repositories"
)

type WorkerLoginAttempts struct {
    WorkerID    uuid.UUID
    AttemptCount int
    LockedUntil *time.Time
    UpdatedAt   time.Time
    CreatedAt   time.Time
}

type WorkerLoginAttemptsRepository interface {
    GetOrCreate(ctx context.Context, workerID uuid.UUID) (*WorkerLoginAttempts, error)
    Increment(ctx context.Context, workerID uuid.UUID, lockDuration, window time.Duration, maxAttempts int) error
    Reset(ctx context.Context, workerID uuid.UUID) error
    IsLocked(ctx context.Context, workerID uuid.UUID) (bool, time.Time, error)
}

type workerLoginAttemptsRepository struct {
    db DB
}

func NewWorkerLoginAttemptsRepository(db DB) WorkerLoginAttemptsRepository {
    return &workerLoginAttemptsRepository{db: db}
}

func (r *workerLoginAttemptsRepository) GetOrCreate(ctx context.Context, workerID uuid.UUID) (*WorkerLoginAttempts, error) {
    query := `
        SELECT worker_id, attempt_count, locked_until, updated_at, created_at
        FROM worker_login_attempts
        WHERE worker_id = $1
    `
    row := r.db.QueryRow(ctx, query, workerID)
    la := &WorkerLoginAttempts{}
    err := row.Scan(
        &la.WorkerID,
        &la.AttemptCount,
        &la.LockedUntil,
        &la.UpdatedAt,
        &la.CreatedAt,
    )
    if err == nil {
        return la, nil
    }
    // Insert fresh
    insert := `
        INSERT INTO worker_login_attempts (worker_id, attempt_count, locked_until, updated_at, created_at)
        VALUES ($1, 0, NULL, NOW(), NOW())
        RETURNING worker_id, attempt_count, locked_until, updated_at, created_at
    `
    row = r.db.QueryRow(ctx, insert, workerID)
    err = row.Scan(
        &la.WorkerID,
        &la.AttemptCount,
        &la.LockedUntil,
        &la.UpdatedAt,
        &la.CreatedAt,
    )
    return la, err
}

func (r *workerLoginAttemptsRepository) Increment(
    ctx context.Context,
    workerID uuid.UUID,
    lockDuration, window time.Duration,
    maxAttempts int,
) error {
    // FIX: Qualify ambiguous columns with 'current.' to prevent SQL error.
    query := `
WITH current AS (
    SELECT worker_id,
           attempt_count,
           locked_until,
           updated_at
    FROM worker_login_attempts
    WHERE worker_id = $1
    FOR UPDATE
)
UPDATE worker_login_attempts
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
WHERE worker_login_attempts.worker_id = current.worker_id
RETURNING worker_login_attempts.worker_id
    `
    _, err := r.db.Exec(ctx, query, workerID, lockDuration, window, maxAttempts)
    return err
}

func (r *workerLoginAttemptsRepository) Reset(ctx context.Context, workerID uuid.UUID) error {
    query := `
        UPDATE worker_login_attempts
        SET attempt_count = 0,
            locked_until = NULL,
            updated_at = NOW()
        WHERE worker_id = $1
    `
    _, err := r.db.Exec(ctx, query, workerID)
    return err
}

func (r *workerLoginAttemptsRepository) IsLocked(ctx context.Context, workerID uuid.UUID) (bool, time.Time, error) {
    query := `
        SELECT locked_until
        FROM worker_login_attempts
        WHERE worker_id = $1
    `
    row := r.db.QueryRow(ctx, query, workerID)
    var lockedUntil *time.Time
    if err := row.Scan(&lockedUntil); err != nil {
        return false, time.Time{}, err
    }
    if lockedUntil != nil && lockedUntil.After(time.Now()) {
        return true, *lockedUntil, nil
    }
    return false, time.Time{}, nil
}
