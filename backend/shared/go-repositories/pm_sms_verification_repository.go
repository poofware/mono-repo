// go-repositories/pm_sms_verification_repository.go
package repositories

import (
    "context"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v4"
    "github.com/poofware/mono-repo/backend/shared/go-models"
)

type PMSMSVerificationRepository interface {
    CreateCode(ctx context.Context, pmID *uuid.UUID, pmPhone, code string, expiresAt time.Time) error
    GetCode(ctx context.Context, pmPhone string) (*models.PMSMSVerificationCode, error)
    DeleteCode(ctx context.Context, id uuid.UUID) error
    IncrementAttempts(ctx context.Context, id uuid.UUID) error
    MarkVerified(ctx context.Context, id uuid.UUID, clientID string) error
    CleanupExpired(ctx context.Context) error

    // Now also checks pm_id if present
    IsCurrentlyVerified(ctx context.Context, pmID *uuid.UUID, pmPhone, clientID string) (bool, *uuid.UUID, error)
}

type pmSMSVerificationRepository struct {
    db DB
}

func NewPMSMSVerificationRepository(db DB) PMSMSVerificationRepository {
    return &pmSMSVerificationRepository{db: db}
}

func (r *pmSMSVerificationRepository) CreateCode(
    ctx context.Context,
    pmID *uuid.UUID,
    pmPhone, code string,
    expiresAt time.Time,
) error {
    q := `
        INSERT INTO pm_sms_verification_codes
            (id, pm_id, pm_phone, verification_code, expires_at, created_at, attempts)
        VALUES ($1, $2, $3, $4, $5, NOW(), 0)
    `
    _, err := r.db.Exec(ctx, q, uuid.New(), pmID, pmPhone, code, expiresAt)
    return err
}

func (r *pmSMSVerificationRepository) GetCode(ctx context.Context, pmPhone string) (*models.PMSMSVerificationCode, error) {
    q := `
        SELECT id, pm_id, pm_phone, verification_code, expires_at, attempts,
               verified, verified_at, verified_by, created_at
        FROM pm_sms_verification_codes
        WHERE pm_phone = $1
        ORDER BY created_at DESC
        LIMIT 1
    `
    row := r.db.QueryRow(ctx, q, pmPhone)
    var rec models.PMSMSVerificationCode
    err := row.Scan(
        &rec.ID,
        &rec.PMID,
        &rec.PMPhone,
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

func (r *pmSMSVerificationRepository) DeleteCode(ctx context.Context, id uuid.UUID) error {
    q := `DELETE FROM pm_sms_verification_codes WHERE id = $1`
    _, err := r.db.Exec(ctx, q, id)
    return err
}

func (r *pmSMSVerificationRepository) IncrementAttempts(ctx context.Context, id uuid.UUID) error {
    q := `UPDATE pm_sms_verification_codes SET attempts = attempts + 1 WHERE id = $1`
    _, err := r.db.Exec(ctx, q, id)
    return err
}

func (r *pmSMSVerificationRepository) MarkVerified(ctx context.Context, id uuid.UUID, clientID string) error {
    q := `
        UPDATE pm_sms_verification_codes
        SET verified = TRUE,
            verified_at = NOW(),
            verified_by = $2
        WHERE id = $1
    `
    _, err := r.db.Exec(ctx, q, id, clientID)
    return err
}

func (r *pmSMSVerificationRepository) CleanupExpired(ctx context.Context) error {
    q := `
        DELETE FROM pm_sms_verification_codes
        WHERE
          (verified = FALSE AND expires_at < NOW())
          OR
          (verified = TRUE AND verified_at + INTERVAL '15 minutes' < NOW())
    `
    _, err := r.db.Exec(ctx, q)
    return err
}

func (r *pmSMSVerificationRepository) IsCurrentlyVerified(
    ctx context.Context,
    pmID *uuid.UUID,
    pmPhone, clientID string,
) (bool, *uuid.UUID, error) {
    if pmID != nil {
        // If pmID is present, require pm_id = that ID and pm_phone = that number
        q := `
            SELECT id
            FROM pm_sms_verification_codes
            WHERE pm_id = $1
              AND pm_phone = $2
              AND verified = TRUE
              AND verified_at + INTERVAL '15 minutes' > NOW()
            ORDER BY created_at DESC
            LIMIT 1
        `
        row := r.db.QueryRow(ctx, q, *pmID, pmPhone)
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

    // Fallback: no pmID => match phone + verified_by=clientID
    q := `
        SELECT id
        FROM pm_sms_verification_codes
        WHERE pm_phone = $1
          AND verified = TRUE
          AND verified_by = $2
          AND verified_at + INTERVAL '15 minutes' > NOW()
        ORDER BY created_at DESC
        LIMIT 1
    `
    row := r.db.QueryRow(ctx, q, pmPhone, clientID)
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
