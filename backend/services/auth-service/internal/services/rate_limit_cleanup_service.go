// meta-service/services/auth-service/internal/services/rate_limit_cleanup_service.go
package services

import (
	"context"

	"github.com/poofware/auth-service/internal/repositories"
	"github.com/poofware/go-utils"
)

// RateLimitCleanupService removes expired rate limit counter keys from the database.
type RateLimitCleanupService interface {
	CleanupDaily(ctx context.Context) error
}

type rateLimitCleanupService struct {
	repo repositories.RateLimitRepository
}

func NewRateLimitCleanupService(repo repositories.RateLimitRepository) RateLimitCleanupService {
	return &rateLimitCleanupService{repo: repo}
}

// CleanupDaily removes expired rate limit keys and logs any errors.
func (s *rateLimitCleanupService) CleanupDaily(ctx context.Context) error {
	logger := utils.Logger

	if err := s.repo.CleanupExpired(ctx); err != nil {
		logger.WithError(err).Error("Failed to cleanup expired rate_limit_attempts")
		return err
	}

	logger.Info("Daily rate limit counter cleanup completed successfully.")
	return nil
}

