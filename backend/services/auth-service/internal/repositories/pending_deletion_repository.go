package repositories

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/auth-service/internal/models"
	repo "github.com/poofware/go-repositories"
)

// PendingDeletionRepository handles CRUD for pending account deletions.
type PendingDeletionRepository interface {
	DB() repo.DB
	Create(ctx context.Context, token string, workerID uuid.UUID, expiresAt time.Time) error
	Get(ctx context.Context, token string) (*models.PendingDeletion, error)
	Delete(ctx context.Context, token string) error
}

type pendingDeletionRepository struct {
	db repo.DB
}

// NewPendingDeletionRepository creates a new repository.
func NewPendingDeletionRepository(db repo.DB) PendingDeletionRepository {
	return &pendingDeletionRepository{db: db}
}

func (r *pendingDeletionRepository) DB() repo.DB { return r.db }

func (r *pendingDeletionRepository) Create(ctx context.Context, token string, workerID uuid.UUID, expiresAt time.Time) error {
	query := `
        INSERT INTO pending_deletions (token, worker_id, expires_at)
        VALUES ($1, $2, $3)
    `
	_, err := r.db.Exec(ctx, query, token, workerID, expiresAt)
	return err
}

func (r *pendingDeletionRepository) Get(ctx context.Context, token string) (*models.PendingDeletion, error) {
	query := `
        SELECT token, worker_id, expires_at
        FROM pending_deletions
        WHERE token = $1
    `
	row := r.db.QueryRow(ctx, query, token)
	var pd models.PendingDeletion
	if err := row.Scan(&pd.Token, &pd.WorkerID, &pd.ExpiresAt); err != nil {
		return nil, err
	}
	return &pd, nil
}

func (r *pendingDeletionRepository) Delete(ctx context.Context, token string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM pending_deletions WHERE token=$1`, token)
	return err
}
