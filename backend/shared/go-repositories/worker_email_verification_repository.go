// go-repositories/worker_email_verification_repository.go
package repositories

import (
    "context"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v4"
    "github.com/poofware/go-models"
)

type WorkerEmailVerificationRepository interface {
    CreateCode(ctx context.Context, workerID *uuid.UUID, workerEmail, code string, expiresAt time.Time) error
    GetCode(ctx context.Context, workerEmail string) (*models.WorkerEmailVerificationCode, error)
    DeleteCode(ctx context.Context, id uuid.UUID) error
    IncrementAttempts(ctx context.Context, id uuid.UUID) error
    MarkVerified(ctx context.Context, id uuid.UUID, clientID string) error
    CleanupExpired(ctx context.Context) error

    IsCurrentlyVerified(ctx context.Context, workerID *uuid.UUID, workerEmail, clientID string) (bool, *uuid.UUID, error)
}

type workerEmailVerificationRepository struct {
    db DB
}

func NewWorkerEmailVerificationRepository(db DB) WorkerEmailVerificationRepository {
    return &workerEmailVerificationRepository{db: db}
}

func (r *workerEmailVerificationRepository) CreateCode(
    ctx context.Context,
    workerID *uuid.UUID,
    workerEmail, code string,
    expiresAt time.Time,
) error {
    q := `
        INSERT INTO worker_email_verification_codes
            (id, worker_id, worker_email, verification_code, expires_at, created_at, attempts)
        VALUES ($1, $2, $3, $4, $5, NOW(), 0)
    `
    _, err := r.db.Exec(ctx, q, uuid.New(), workerID, workerEmail, code, expiresAt)
    return err
}

func (r *workerEmailVerificationRepository) GetCode(ctx context.Context, workerEmail string) (*models.WorkerEmailVerificationCode, error) {
    q := `
        SELECT id, worker_id, worker_email, verification_code, expires_at, attempts,
               verified, verified_at, verified_by, created_at
        FROM worker_email_verification_codes
        WHERE worker_email = $1
        ORDER BY created_at DESC
        LIMIT 1
    `
    row := r.db.QueryRow(ctx, q, workerEmail)
    var rec models.WorkerEmailVerificationCode
    err := row.Scan(
        &rec.ID,
        &rec.WorkerID,
        &rec.WorkerEmail,
        &rec.VerificationCode,
        &rec.ExpiresAt,
        &rec.Attempts,
        &rec.Verified,
        &rec.VerifiedAt,
        &rec.VerifiedBy,
        &rec.CreatedAt,
    )
    if err != nil {
        return nil, err
    }
    return &rec, nil
}

func (r *workerEmailVerificationRepository) DeleteCode(ctx context.Context, id uuid.UUID) error {
    q := `DELETE FROM worker_email_verification_codes WHERE id = $1`
    _, err := r.db.Exec(ctx, q, id)
    return err
}

func (r *workerEmailVerificationRepository) IncrementAttempts(ctx context.Context, id uuid.UUID) error {
    q := `UPDATE worker_email_verification_codes SET attempts = attempts + 1 WHERE id = $1`
    _, err := r.db.Exec(ctx, q, id)
    return err
}

func (r *workerEmailVerificationRepository) MarkVerified(ctx context.Context, id uuid.UUID, clientID string) error {
    q := `
        UPDATE worker_email_verification_codes
        SET verified = TRUE,
            verified_at = NOW(),
            verified_by = $2
        WHERE id = $1
    `
    _, err := r.db.Exec(ctx, q, id, clientID)
    return err
}

func (r *workerEmailVerificationRepository) CleanupExpired(ctx context.Context) error {
    q := `
        DELETE FROM worker_email_verification_codes
        WHERE
          (verified = FALSE AND expires_at < NOW())
          OR
          (verified = TRUE AND verified_at + INTERVAL '15 minutes' < NOW())
    `
    _, err := r.db.Exec(ctx, q)
    return err
}

// If workerID is present, we check for that ID and that email. Otherwise fallback to clientID-based verification.
func (r *workerEmailVerificationRepository) IsCurrentlyVerified(
    ctx context.Context,
    workerID *uuid.UUID,
    workerEmail, clientID string,
) (bool, *uuid.UUID, error) {
    if workerID != nil {
        q := `
            SELECT id
            FROM worker_email_verification_codes
            WHERE worker_id = $1
              AND worker_email = $2
              AND verified = TRUE
              AND verified_at + INTERVAL '15 minutes' > NOW()
            ORDER BY created_at DESC
            LIMIT 1
        `
        row := r.db.QueryRow(ctx, q, *workerID, workerEmail)
        var id uuid.UUID
        err := row.Scan(&id)
        if err != nil {
            if err == pgx.ErrNoRows {
                return false, nil, nil
            }
            return false, nil, err
        }
        return true, &id, nil
    }

    q := `
        SELECT id
        FROM worker_email_verification_codes
        WHERE worker_email = $1
          AND verified = TRUE
          AND verified_by = $2
          AND verified_at + INTERVAL '15 minutes' > NOW()
        ORDER BY created_at DESC
        LIMIT 1
    `
    row := r.db.QueryRow(ctx, q, workerEmail, clientID)
    var id uuid.UUID
    err := row.Scan(&id)
    if err != nil {
        if err == pgx.ErrNoRows {
            return false, nil, nil
        }
        return false, nil, err
    }
    return true, &id, nil
}
