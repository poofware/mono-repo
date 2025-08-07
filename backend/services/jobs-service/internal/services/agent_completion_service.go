package services

import (
	"context"
	"errors"
	"time"
	"strings"

	"github.com/google/uuid"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
)

// NEW: Specific errors for the agent completion flow.
var (
	ErrTokenNotFound = errors.New("token_not_found")
	ErrTokenUsed     = errors.New("token_used")
	ErrTokenExpired  = errors.New("token_expired")
	ErrJobNotOpen    = errors.New("job_not_open")
)

type AgentCompletionService struct {
	repo     repositories.AgentJobCompletionRepository
	instRepo repositories.JobInstanceRepository
}

func NewAgentCompletionService(repo repositories.AgentJobCompletionRepository, instRepo repositories.JobInstanceRepository) *AgentCompletionService {
	return &AgentCompletionService{repo: repo, instRepo: instRepo}
}

// CompleteByToken validates the token and completes the associated job instance.
// MODIFIED: Returns specific errors for different failure scenarios.
func (s *AgentCompletionService) CompleteByToken(ctx context.Context, token string) (*models.JobInstance, *uuid.UUID, error) {
	rec, err := s.repo.GetByToken(ctx, token)
	if err != nil {
		return nil, nil, ErrTokenNotFound // More specific error
	}
	if rec == nil {
		return nil, nil, ErrTokenNotFound
	}
	if rec.CompletedAt != nil {
		return nil, nil, ErrTokenUsed
	}
	if time.Now().After(rec.ExpiresAt) {
		return nil, nil, ErrTokenExpired
	}

	// MODIFIED: Check the job instance status BEFORE marking the token as used.
	// This handles the race condition where another agent claims the job.
	inst, err := s.instRepo.GetByID(ctx, rec.JobInstanceID)
	if err != nil {
		return nil, nil, err
	}
	if inst == nil || inst.Status != models.InstanceStatusOpen {
		return nil, nil, ErrJobNotOpen
	}

	// Now that we've confirmed the job is available, mark the token and complete the job.
	if _, err = s.repo.MarkCompleted(ctx, rec.ID); err != nil {
		return nil, nil, err
	}

	completedInst, err := s.instRepo.CompleteByAgent(ctx, rec.JobInstanceID, rec.AgentID)
	if err != nil {
		// This could be a row version conflict if two agents clicked at the exact same moment.
		// The first one would have changed the status from OPEN, so this CompleteByAgent would fail.
		// We can treat this the same as the job not being open.
		if strings.Contains(err.Error(), "job_not_open") {
			return nil, nil, ErrJobNotOpen
		}
		return nil, nil, err
	}
	return completedInst, &rec.AgentID, nil
}


// CleanupExpired removes tokens past their expiration.
func (s *AgentCompletionService) CleanupExpired(ctx context.Context) (int64, error) {
	return s.repo.CleanupExpiredTokens(ctx, time.Now())
}
