package repositories

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/services/auth-service/internal/models"
	repo "github.com/poofware/mono-repo/backend/shared/go-repositories"
)

// PendingWorkerDeletionRepository handles CRUD for pending account deletions.
type PendingWorkerDeletionRepository interface {
	DB() repo.DB
	Create(ctx context.Context, token string, workerID uuid.UUID, expiresAt time.Time) error
	Get(ctx context.Context, token string) (*models.PendingWorkerDeletion, error)
	Delete(ctx context.Context, token string) error
}

type pendingWorkerDeletionRepository struct {
	db repo.DB
}

// NewPendingWorkerDeletionRepository creates a new repository.
func NewPendingWorkerDeletionRepository(db repo.DB) PendingWorkerDeletionRepository {
	return &pendingWorkerDeletionRepository{db: db}
}

func (r *pendingWorkerDeletionRepository) DB() repo.DB { return r.db }

func (r *pendingWorkerDeletionRepository) Create(ctx context.Context, token string, workerID uuid.UUID, expiresAt time.Time) error {
	query := `
        INSERT INTO pending_worker_deletions (token, worker_id, expires_at)
        VALUES ($1, $2, $3)
    `
	_, err := r.db.Exec(ctx, query, token, workerID, expiresAt)
	return err
}

func (r *pendingWorkerDeletionRepository) Get(ctx context.Context, token string) (*models.PendingWorkerDeletion, error) {
	query := `
        SELECT token, worker_id, expires_at
        FROM pending_worker_deletions
        WHERE token = $1
    `
	row := r.db.QueryRow(ctx, query, token)
	var pd models.PendingWorkerDeletion
	if err := row.Scan(&pd.Token, &pd.WorkerID, &pd.ExpiresAt); err != nil {
		return nil, err
	}
	return &pd, nil
}

func (r *pendingWorkerDeletionRepository) Delete(ctx context.Context, token string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM pending_worker_deletions WHERE token=$1`, token)
	return err
}
