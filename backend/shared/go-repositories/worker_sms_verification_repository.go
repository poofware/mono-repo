// go-repositories/worker_sms_verification_repository.go
package repositories

import (
    "context"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v4"
    "github.com/poofware/mono-repo/backend/shared/go-models"
)

type WorkerSMSVerificationRepository interface {
    CreateCode(ctx context.Context, workerID *uuid.UUID, workerPhone, code string, expiresAt time.Time) error
    GetCode(ctx context.Context, workerPhone string) (*models.WorkerSMSVerificationCode, error)
    DeleteCode(ctx context.Context, id uuid.UUID) error
    IncrementAttempts(ctx context.Context, id uuid.UUID) error
    MarkVerified(ctx context.Context, id uuid.UUID, clientID string) error
    CleanupExpired(ctx context.Context) error

    IsCurrentlyVerified(ctx context.Context, workerID *uuid.UUID, workerPhone, clientID string) (bool, *uuid.UUID, error)
}

type workerSMSVerificationRepository struct {
    db DB
}

func NewWorkerSMSVerificationRepository(db DB) WorkerSMSVerificationRepository {
    return &workerSMSVerificationRepository{db: db}
}

func (r *workerSMSVerificationRepository) CreateCode(
    ctx context.Context,
    workerID *uuid.UUID,
    workerPhone, code string,
    expiresAt time.Time,
) error {
    q := `
        INSERT INTO worker_sms_verification_codes
            (id, worker_id, worker_phone, verification_code, expires_at, created_at, attempts)
        VALUES ($1, $2, $3, $4, $5, NOW(), 0)
    `
    _, err := r.db.Exec(ctx, q, uuid.New(), workerID, workerPhone, code, expiresAt)
    return err
}

func (r *workerSMSVerificationRepository) GetCode(ctx context.Context, workerPhone string) (*models.WorkerSMSVerificationCode, error) {
    q := `
        SELECT id, worker_id, worker_phone, verification_code, expires_at, attempts,
               verified, verified_at, verified_by, created_at
        FROM worker_sms_verification_codes
        WHERE worker_phone = $1
        ORDER BY created_at DESC
        LIMIT 1
    `
    row := r.db.QueryRow(ctx, q, workerPhone)
    var rec models.WorkerSMSVerificationCode
    err := row.Scan(
        &rec.ID,
        &rec.WorkerID,
        &rec.WorkerPhone,
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

func (r *workerSMSVerificationRepository) DeleteCode(ctx context.Context, id uuid.UUID) error {
    q := `DELETE FROM worker_sms_verification_codes WHERE id = $1`
    _, err := r.db.Exec(ctx, q, id)
    return err
}

func (r *workerSMSVerificationRepository) IncrementAttempts(ctx context.Context, id uuid.UUID) error {
    q := `UPDATE worker_sms_verification_codes SET attempts = attempts + 1 WHERE id = $1`
    _, err := r.db.Exec(ctx, q, id)
    return err
}

func (r *workerSMSVerificationRepository) MarkVerified(ctx context.Context, id uuid.UUID, clientID string) error {
    q := `
        UPDATE worker_sms_verification_codes
        SET verified = TRUE,
            verified_at = NOW(),
            verified_by = $2
        WHERE id = $1
    `
    _, err := r.db.Exec(ctx, q, id, clientID)
    return err
}

func (r *workerSMSVerificationRepository) CleanupExpired(ctx context.Context) error {
    q := `
        DELETE FROM worker_sms_verification_codes
        WHERE
          (verified = FALSE AND expires_at < NOW())
          OR
          (verified = TRUE AND verified_at + INTERVAL '15 minutes' < NOW())
    `
    _, err := r.db.Exec(ctx, q)
    return err
}

// If workerID is present, we require that ID and phone; otherwise rely on clientID-based verification.
func (r *workerSMSVerificationRepository) IsCurrentlyVerified(
    ctx context.Context,
    workerID *uuid.UUID,
    workerPhone, clientID string,
) (bool, *uuid.UUID, error) {
    if workerID != nil {
        q := `
            SELECT id
            FROM worker_sms_verification_codes
            WHERE worker_id = $1
              AND worker_phone = $2
              AND verified = TRUE
              AND verified_at + INTERVAL '15 minutes' > NOW()
            ORDER BY created_at DESC
            LIMIT 1
        `
        row := r.db.QueryRow(ctx, q, *workerID, workerPhone)
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
        FROM worker_sms_verification_codes
        WHERE worker_phone = $1
          AND verified = TRUE
          AND verified_by = $2
          AND verified_at + INTERVAL '15 minutes' > NOW()
        ORDER BY created_at DESC
        LIMIT 1
    `
    row := r.db.QueryRow(ctx, q, workerPhone, clientID)
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
