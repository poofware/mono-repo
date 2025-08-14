// go-repositories/pm_email_verification_repository.go
package repositories

import (
    "context"
    "time"

    "github.com/google/uuid"
    "github.com/jackc/pgx/v4"
    "github.com/poofware/mono-repo/backend/shared/go-models"
)

type PMEmailVerificationRepository interface {
    CreateCode(ctx context.Context, pmID *uuid.UUID, pmEmail, code string, expiresAt time.Time) error
    GetCode(ctx context.Context, pmEmail string) (*models.PMEmailVerificationCode, error)
    DeleteCode(ctx context.Context, id uuid.UUID) error
    IncrementAttempts(ctx context.Context, id uuid.UUID) error
    MarkVerified(ctx context.Context, id uuid.UUID, clientID string) error
    CleanupExpired(ctx context.Context) error

    // Now supports checking by pmID (if present) or clientID:
    IsCurrentlyVerified(ctx context.Context, pmID *uuid.UUID, pmEmail, clientID string) (bool, *uuid.UUID, error)
}

type pmEmailVerificationRepository struct {
    db DB
}

func NewPMEmailVerificationRepository(db DB) PMEmailVerificationRepository {
    return &pmEmailVerificationRepository{db: db}
}

func (r *pmEmailVerificationRepository) CreateCode(
    ctx context.Context,
    pmID *uuid.UUID,
    pmEmail, code string,
    expiresAt time.Time,
) error {
    q := `
        INSERT INTO pm_email_verification_codes
            (id, pm_id, pm_email, verification_code, expires_at, created_at, attempts)
        VALUES ($1, $2, $3, $4, $5, NOW(), 0)
    `
    _, err := r.db.Exec(ctx, q, uuid.New(), pmID, pmEmail, code, expiresAt)
    return err
}

func (r *pmEmailVerificationRepository) GetCode(ctx context.Context, pmEmail string) (*models.PMEmailVerificationCode, error) {
    q := `
        SELECT id, pm_id, pm_email, verification_code, expires_at, attempts,
               verified, verified_at, verified_by, created_at
        FROM pm_email_verification_codes
        WHERE pm_email = $1
        ORDER BY created_at DESC
        LIMIT 1
    `
    row := r.db.QueryRow(ctx, q, pmEmail)
    var rec models.PMEmailVerificationCode
    err := row.Scan(
        &rec.ID,
        &rec.PMID,
        &rec.PMEmail,
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

func (r *pmEmailVerificationRepository) DeleteCode(ctx context.Context, id uuid.UUID) error {
    q := `DELETE FROM pm_email_verification_codes WHERE id = $1`
    _, err := r.db.Exec(ctx, q, id)
    return err
}

func (r *pmEmailVerificationRepository) IncrementAttempts(ctx context.Context, id uuid.UUID) error {
    q := `UPDATE pm_email_verification_codes SET attempts = attempts + 1 WHERE id = $1`
    _, err := r.db.Exec(ctx, q, id)
    return err
}

func (r *pmEmailVerificationRepository) MarkVerified(ctx context.Context, id uuid.UUID, clientID string) error {
    q := `
        UPDATE pm_email_verification_codes
        SET verified = TRUE,
            verified_at = NOW(),
            verified_by = $2
        WHERE id = $1
    `
    _, err := r.db.Exec(ctx, q, id, clientID)
    return err
}

func (r *pmEmailVerificationRepository) CleanupExpired(ctx context.Context) error {
    q := `
        DELETE FROM pm_email_verification_codes
        WHERE
          (verified = FALSE AND expires_at < NOW())
          OR
          (verified = TRUE AND verified_at + INTERVAL '15 minutes' < NOW())
    `
    _, err := r.db.Exec(ctx, q)
    return err
}

// IsCurrentlyVerified checks if there's a row for the given email that has
// not yet expired, is verified, and matches either pm_id (if present)
// or else verified_by=clientID if pm_id is nil.
func (r *pmEmailVerificationRepository) IsCurrentlyVerified(
    ctx context.Context,
    pmID *uuid.UUID,
    pmEmail, clientID string,
) (bool, *uuid.UUID, error) {
    if pmID != nil {
        // If we have a pmID from JWT, then we require pm_id = <that ID> and pm_email = <that email>.
        q := `
            SELECT id
            FROM pm_email_verification_codes
            WHERE pm_id = $1
              AND pm_email = $2
              AND verified = TRUE
              AND verified_at + INTERVAL '15 minutes' > NOW()
            ORDER BY created_at DESC
            LIMIT 1
        `
        row := r.db.QueryRow(ctx, q, *pmID, pmEmail)
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

    // If pmID is nil, fallback to matching pm_email + verified_by=clientID.
    q := `
        SELECT id
        FROM pm_email_verification_codes
        WHERE pm_email = $1
          AND verified = TRUE
          AND verified_by = $2
          AND verified_at + INTERVAL '15 minutes' > NOW()
        ORDER BY created_at DESC
        LIMIT 1
    `
    row := r.db.QueryRow(ctx, q, pmEmail, clientID)
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
