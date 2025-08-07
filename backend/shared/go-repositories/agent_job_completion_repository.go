// go-repositories/agent_job_completion_repository.go

package repositories

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/poofware/mono-repo/backend/shared/go-models"
)

type AgentJobCompletionRepository interface {
	Create(ctx context.Context, rec *models.AgentJobCompletion) error
	GetByToken(ctx context.Context, token string) (*models.AgentJobCompletion, error)
	MarkCompleted(ctx context.Context, id uuid.UUID) (pgconn.CommandTag, error)
	CleanupExpiredTokens(ctx context.Context, now time.Time) (int64, error)
}

type agentJobCompletionRepo struct {
	db DB
}

func NewAgentJobCompletionRepository(db DB) AgentJobCompletionRepository {
	return &agentJobCompletionRepo{db: db}
}

func (r *agentJobCompletionRepo) Create(ctx context.Context, rec *models.AgentJobCompletion) error {
	_, err := r.db.Exec(ctx, `
        INSERT INTO agent_job_completions (
            id, job_instance_id, agent_id, token, expires_at
        ) VALUES ($1,$2,$3,$4,$5)
    `, rec.ID, rec.JobInstanceID, rec.AgentID, rec.Token, rec.ExpiresAt)
	return err
}

func (r *agentJobCompletionRepo) GetByToken(ctx context.Context, token string) (*models.AgentJobCompletion, error) {
	row := r.db.QueryRow(ctx, `SELECT id, job_instance_id, agent_id, token, expires_at, completed_at FROM agent_job_completions WHERE token=$1`, token)
	var rec models.AgentJobCompletion
	if err := row.Scan(&rec.ID, &rec.JobInstanceID, &rec.AgentID, &rec.Token, &rec.ExpiresAt, &rec.CompletedAt); err != nil {
		return nil, err
	}
	return &rec, nil
}

func (r *agentJobCompletionRepo) MarkCompleted(ctx context.Context, id uuid.UUID) (pgconn.CommandTag, error) {
	return r.db.Exec(ctx, `UPDATE agent_job_completions SET completed_at=NOW() WHERE id=$1 AND completed_at IS NULL`, id)
}

func (r *agentJobCompletionRepo) CleanupExpiredTokens(ctx context.Context, now time.Time) (int64, error) {
	cmd, err := r.db.Exec(ctx, `DELETE FROM agent_job_completions WHERE expires_at < $1`, now)
	if err != nil {
		return 0, err
	}
	return cmd.RowsAffected(), nil
}
