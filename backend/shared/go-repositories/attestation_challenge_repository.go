// go-repositories/attestation_challenge_repository.go
package repositories

import (
	"context"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/mono-repo/backend/shared/go-models"
)

// AttestationChallengeRepository manages the lifecycle of single-use attestation challenges.
type AttestationChallengeRepository interface {
	// Create stores a new challenge with a specific TTL.
	Create(ctx context.Context, challenge *models.AttestationChallenge) error
	// Consume retrieves a challenge by its ID and immediately deletes it to prevent reuse.
	// It returns the raw challenge bytes, the platform string, and a nil error if found.
	// If the challenge is not found or expired, it returns nil, "", nil.
	Consume(ctx context.Context, id uuid.UUID) (rawChallenge []byte, platform string, err error)
	// CleanupExpired removes all challenges that have passed their expires_at timestamp.
	CleanupExpired(ctx context.Context) error
}

type attestationChallengeRepo struct {
	db DB
}

// NewAttestationChallengeRepository creates a new repository for attestation challenges.
func NewAttestationChallengeRepository(db DB) AttestationChallengeRepository {
	return &attestationChallengeRepo{db: db}
}

func (r *attestationChallengeRepo) Create(ctx context.Context, c *models.AttestationChallenge) error {
	q := `
        INSERT INTO attestation_challenges (id, raw_challenge, platform, expires_at)
        VALUES ($1, $2, $3, $4)
    `
	_, err := r.db.Exec(ctx, q, c.ID, c.RawChallenge, c.Platform, c.ExpiresAt)
	return err
}

func (r *attestationChallengeRepo) Consume(ctx context.Context, id uuid.UUID) ([]byte, string, error) {
	q := `
        DELETE FROM attestation_challenges
        WHERE id = $1 AND expires_at > NOW()
        RETURNING raw_challenge, platform
    `
	row := r.db.QueryRow(ctx, q, id)
	var rawChallenge []byte
	var platform string
	err := row.Scan(&rawChallenge, &platform)
	if err == pgx.ErrNoRows {
		return nil, "", nil
	}
	if err != nil {
		return nil, "", err
	}
	return rawChallenge, platform, nil
}

func (r *attestationChallengeRepo) CleanupExpired(ctx context.Context) error {
	q := `DELETE FROM attestation_challenges WHERE expires_at < NOW()`
	_, err := r.db.Exec(ctx, q)
	return err
}
