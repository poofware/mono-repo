package repositories

import (
	"context"
	"time"

	"github.com/jackc/pgx/v4"
)

type AttestationRepository interface {
	SaveKey(ctx context.Context, keyID, pub []byte) error
	LookupKey(ctx context.Context, keyID []byte) ([]byte, error)
	UpdateLastSeen(ctx context.Context, keyID []byte) error
}

type attestationRepo struct {
	db DB
}

func NewAttestationRepository(db DB) AttestationRepository {
	return &attestationRepo{db: db}
}

func (r *attestationRepo) SaveKey(ctx context.Context, keyID, pub []byte) error {
	q := `
INSERT INTO app_attest_keys (key_id, public_key, created_at, last_seen)
VALUES ($1, $2, NOW(), NOW())
ON CONFLICT (key_id)
DO UPDATE SET public_key = EXCLUDED.public_key, last_seen=NOW()
`
	_, err := r.db.Exec(ctx, q, keyID, pub)
	return err
}

func (r *attestationRepo) LookupKey(ctx context.Context, keyID []byte) ([]byte, error) {
	q := `
SELECT public_key
FROM app_attest_keys
WHERE key_id=$1
`
	row := r.db.QueryRow(ctx, q, keyID)
	var pub []byte
	err := row.Scan(&pub)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return pub, nil
}

func (r *attestationRepo) UpdateLastSeen(ctx context.Context, keyID []byte) error {
	q := `
UPDATE app_attest_keys
SET last_seen=$2
WHERE key_id=$1
`
	_, err := r.db.Exec(ctx, q, keyID, time.Now())
	return err
}

