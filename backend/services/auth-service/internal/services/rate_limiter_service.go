// meta-service/services/auth-service/internal/services/rate_limiter_service.go
package services

import (
	"context"
	"fmt"

	"github.com/poofware/mono-repo/backend/services/auth-service/internal/config"
	"github.com/poofware/mono-repo/backend/services/auth-service/internal/repositories"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// RateLimiterService provides a high-level interface for checking various rate limits.
type RateLimiterService interface {
	CheckSMSRateLimits(ctx context.Context, ip, phoneNumber string) error
	CheckEmailRateLimits(ctx context.Context, ip, emailAddress string) error
}

type rateLimiterService struct {
	repo repositories.RateLimitRepository
	cfg  *config.Config
}

func NewRateLimiterService(repo repositories.RateLimitRepository, cfg *config.Config) RateLimiterService {
	return &rateLimiterService{repo: repo, cfg: cfg}
}

// CheckSMSRateLimits checks global, per-IP, and per-phone-number limits for SMS requests.
func (s *rateLimiterService) CheckSMSRateLimits(ctx context.Context, ip, phoneNumber string) error {
	// 1. Global limit
	globalKey := "sms:global"
	allowed, err := s.repo.IncrementAndCheck(ctx, globalKey, s.cfg.GlobalSMSLimitPerHour, s.cfg.RateLimitWindow)
	if err != nil {
		return err
	}
	if !allowed {
		utils.Logger.Warnf("Global SMS rate limit exceeded (key: %s)", globalKey)
		return utils.ErrRateLimitExceeded
	}

	// 2. Per-IP limit
	ipKey := fmt.Sprintf("sms:ip:%s", ip)
	allowed, err = s.repo.IncrementAndCheck(ctx, ipKey, s.cfg.SMSLimitPerIPPerHour, s.cfg.RateLimitWindow)
	if err != nil {
		return err
	}
	if !allowed {
		utils.Logger.Warnf("Per-IP SMS rate limit exceeded (key: %s)", ipKey)
		return utils.ErrRateLimitExceeded
	}

	// 3. Per-destination limit
	phoneKey := fmt.Sprintf("sms:phone:%s", phoneNumber)
	allowed, err = s.repo.IncrementAndCheck(ctx, phoneKey, s.cfg.SMSLimitPerNumberPerHour, s.cfg.RateLimitWindow)
	if err != nil {
		return err
	}
	if !allowed {
		utils.Logger.Warnf("Per-phone SMS rate limit exceeded (key: %s)", phoneKey)
		return utils.ErrRateLimitExceeded
	}

	return nil
}

// CheckEmailRateLimits checks global, per-IP, and per-email limits for email requests.
func (s *rateLimiterService) CheckEmailRateLimits(ctx context.Context, ip, emailAddress string) error {
	// 1. Global limit
	globalKey := "email:global"
	allowed, err := s.repo.IncrementAndCheck(ctx, globalKey, s.cfg.GlobalEmailLimitPerHour, s.cfg.RateLimitWindow)
	if err != nil {
		return err
	}
	if !allowed {
		utils.Logger.Warnf("Global email rate limit exceeded (key: %s)", globalKey)
		return utils.ErrRateLimitExceeded
	}

	// 2. Per-IP limit
	ipKey := fmt.Sprintf("email:ip:%s", ip)
	allowed, err = s.repo.IncrementAndCheck(ctx, ipKey, s.cfg.EmailLimitPerIPPerHour, s.cfg.RateLimitWindow)
	if err != nil {
		return err
	}
	if !allowed {
		utils.Logger.Warnf("Per-IP email rate limit exceeded (key: %s)", ipKey)
		return utils.ErrRateLimitExceeded
	}

	// 3. Per-destination limit
	emailKey := fmt.Sprintf("email:address:%s", emailAddress)
	allowed, err = s.repo.IncrementAndCheck(ctx, emailKey, s.cfg.EmailLimitPerEmailPerHour, s.cfg.RateLimitWindow)
	if err != nil {
		return err
	}
	if !allowed {
		utils.Logger.Warnf("Per-email rate limit exceeded (key: %s)", emailKey)
		return utils.ErrRateLimitExceeded
	}

	return nil
}

