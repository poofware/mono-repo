package repositories

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/services/auth-service/internal/models"
	repo "github.com/poofware/mono-repo/backend/shared/go-repositories"
)

// PendingPMDeletionRepository handles CRUD for pending PM account deletions.
type PendingPMDeletionRepository interface {
	DB() repo.DB
	Create(ctx context.Context, token string, pmID uuid.UUID, expiresAt time.Time) error
	Get(ctx context.Context, token string) (*models.PendingPMDeletion, error)
	Delete(ctx context.Context, token string) error
}

type pendingPMDeletionRepository struct {
	db repo.DB
}

// NewPendingPMDeletionRepository creates a new repository.
func NewPendingPMDeletionRepository(db repo.DB) PendingPMDeletionRepository {
	return &pendingPMDeletionRepository{db: db}
}

func (r *pendingPMDeletionRepository) DB() repo.DB { return r.db }

func (r *pendingPMDeletionRepository) Create(ctx context.Context, token string, pmID uuid.UUID, expiresAt time.Time) error {
	query := `
        INSERT INTO pending_pm_deletions (token, pm_id, expires_at)
        VALUES ($1, $2, $3)
    `
	_, err := r.db.Exec(ctx, query, token, pmID, expiresAt)
	return err
}

func (r *pendingPMDeletionRepository) Get(ctx context.Context, token string) (*models.PendingPMDeletion, error) {
	query := `
        SELECT token, pm_id, expires_at
        FROM pending_pm_deletions
        WHERE token = $1
    `
	row := r.db.QueryRow(ctx, query, token)
	var pd models.PendingPMDeletion
	if err := row.Scan(&pd.Token, &pd.PMID, &pd.ExpiresAt); err != nil {
		return nil, err
	}
	return &pd, nil
}

func (r *pendingPMDeletionRepository) Delete(ctx context.Context, token string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM pending_pm_deletions WHERE token=$1`, token)
	return err
}
