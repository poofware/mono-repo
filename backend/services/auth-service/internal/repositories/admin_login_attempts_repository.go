// meta-service/services/auth-service/internal/repositories/admin_login_attempts_repository.go
package repositories

import (
    "context"
    "time"

    "github.com/google/uuid"
    . "github.com/poofware/go-repositories"
)

type AdminLoginAttempts struct {
    AdminID      uuid.UUID
    AttemptCount int
    LockedUntil  *time.Time
    UpdatedAt    time.Time
    CreatedAt    time.Time
}

type AdminLoginAttemptsRepository interface {
    GetOrCreate(ctx context.Context, adminID uuid.UUID) (*AdminLoginAttempts, error)
    Increment(ctx context.Context, adminID uuid.UUID, lockDuration, window time.Duration, maxAttempts int) error
    Reset(ctx context.Context, adminID uuid.UUID) error
    IsLocked(ctx context.Context, adminID uuid.UUID) (bool, time.Time, error)
}

type adminLoginAttemptsRepository struct {
    db DB
}

func NewAdminLoginAttemptsRepository(db DB) AdminLoginAttemptsRepository {
    return &adminLoginAttemptsRepository{db: db}
}

func (r *adminLoginAttemptsRepository) GetOrCreate(ctx context.Context, adminID uuid.UUID) (*AdminLoginAttempts, error) {
    query := `
        SELECT admin_id, attempt_count, locked_until, updated_at, created_at
        FROM admin_login_attempts
        WHERE admin_id = $1
    `
    row := r.db.QueryRow(ctx, query, adminID)
    la := &AdminLoginAttempts{}
    err := row.Scan(
        &la.AdminID,
        &la.AttemptCount,
        &la.LockedUntil,
        &la.UpdatedAt,
        &la.CreatedAt,
    )
    if err == nil {
        return la, nil
    }

    insert := `
        INSERT INTO admin_login_attempts (admin_id, attempt_count, locked_until, updated_at, created_at)
        VALUES ($1, 0, NULL, NOW(), NOW())
        RETURNING admin_id, attempt_count, locked_until, updated_at, created_at
    `
    row = r.db.QueryRow(ctx, insert, adminID)
    err = row.Scan(
        &la.AdminID,
        &la.AttemptCount,
        &la.LockedUntil,
        &la.UpdatedAt,
        &la.CreatedAt,
    )
    return la, err
}

func (r *adminLoginAttemptsRepository) Increment(
    ctx context.Context,
    adminID uuid.UUID,
    lockDuration, window time.Duration,
    maxAttempts int,
) error {
    query := `
        WITH current AS (
            SELECT admin_id, attempt_count, locked_until, updated_at
            FROM admin_login_attempts
            WHERE admin_id = $1 FOR UPDATE
        )
        UPDATE admin_login_attempts
        SET attempt_count = CASE
            WHEN (current.locked_until IS NOT NULL AND current.locked_until > NOW()) THEN current.attempt_count
            ELSE CASE
                WHEN (NOW() - current.updated_at) > $3 THEN 1
                ELSE current.attempt_count + 1
            END
        END,
        locked_until = CASE
            WHEN (current.locked_until IS NOT NULL AND current.locked_until > NOW()) THEN current.locked_until
            ELSE CASE
                WHEN ((NOW() - current.updated_at) <= $3 AND (current.attempt_count + 1) >= $4) THEN NOW() + $2
                ELSE NULL
            END
        END,
        updated_at = NOW()
        FROM current
        WHERE admin_login_attempts.admin_id = current.admin_id
    `
    _, err := r.db.Exec(ctx, query, adminID, lockDuration, window, maxAttempts)
    return err
}

func (r *adminLoginAttemptsRepository) Reset(ctx context.Context, adminID uuid.UUID) error {
    query := `UPDATE admin_login_attempts SET attempt_count = 0, locked_until = NULL, updated_at = NOW() WHERE admin_id = $1`
    _, err := r.db.Exec(ctx, query, adminID)
    return err
}

func (r *adminLoginAttemptsRepository) IsLocked(ctx context.Context, adminID uuid.UUID) (bool, time.Time, error) {
    query := `SELECT locked_until FROM admin_login_attempts WHERE admin_id = $1`
    row := r.db.QueryRow(ctx, query, adminID)
    var lockedUntil *time.Time
    if err := row.Scan(&lockedUntil); err != nil {
        return false, time.Time{}, err
    }
    if lockedUntil != nil && lockedUntil.After(time.Now()) {
        return true, *lockedUntil, nil
    }
    return false, time.Time{}, nil
}