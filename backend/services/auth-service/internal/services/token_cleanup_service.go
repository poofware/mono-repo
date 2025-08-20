// token_cleanup_service.go (updated)
package services

import (
    "context"
    "errors"
    "io"
    "strings"
    "time"

    "github.com/jackc/pgconn"
    "github.com/poofware/mono-repo/backend/services/auth-service/internal/repositories"
    "github.com/poofware/mono-repo/backend/shared/go-utils"
)

// ────────────────────────────────────────────────────────────
// Retry policy – one retry on transient network errors (EOF,   
// closed‑connection) with a small back‑off.                    
// ────────────────────────────────────────────────────────────
const cleanupRetryDelay = 3 * time.Second

// TokenCleanupService removes expired refresh tokens each night.
type TokenCleanupService interface {
    CleanupDaily(ctx context.Context) error
}

type tokenCleanupService struct {
    pmTokenRepo     repositories.PMTokenRepository
    workerTokenRepo repositories.WorkerTokenRepository
    adminTokenRepo  repositories.AdminTokenRepository // NEW
}

func NewTokenCleanupService(
    pmTokenRepo repositories.PMTokenRepository,
    workerTokenRepo repositories.WorkerTokenRepository,
    adminTokenRepo repositories.AdminTokenRepository, // NEW
) TokenCleanupService {
    return &tokenCleanupService{
        pmTokenRepo:     pmTokenRepo,
        workerTokenRepo: workerTokenRepo,
        adminTokenRepo:  adminTokenRepo, // NEW
    }
}

// runWithRetry executes op(ctx) and, if it returns a transient network
// error (EOF, pgconn safe‑to‑retry, or the common closed‑connection
// message), waits a moment then retries **once**.
func (s *tokenCleanupService) runWithRetry(
    ctx context.Context,
    op func(context.Context) error,
) error {
    if err := op(ctx); err != nil {
        // Decide whether the error is safe to retry.
        if errors.Is(err, io.EOF) || pgconn.SafeToRetry(err) ||
            strings.Contains(err.Error(), "connection was closed") {
            utils.Logger.WithError(err).Warn("token cleanup hit transient DB error; retrying once")
            time.Sleep(cleanupRetryDelay)
            return op(ctx)
        }
        return err
    }
    return nil
}

// CleanupDaily removes expired tokens from all user type tables.
func (s *tokenCleanupService) CleanupDaily(ctx context.Context) error {
    logger := utils.Logger

    // 1) Cleanup normal expired PM tokens
    if err := s.runWithRetry(ctx, s.pmTokenRepo.CleanupExpiredRefreshTokens); err != nil {
        logger.WithError(err).Error("Failed to cleanup expired pm_refresh_tokens")
        return err
    }

    // 2) Cleanup normal expired Worker tokens
    if err := s.runWithRetry(ctx, s.workerTokenRepo.CleanupExpiredRefreshTokens); err != nil {
        logger.WithError(err).Error("Failed to cleanup expired worker_refresh_tokens")
        return err
    }

    // 3) Cleanup normal expired Admin tokens (NEW)
    if err := s.runWithRetry(ctx, s.adminTokenRepo.CleanupExpiredRefreshTokens); err != nil {
        logger.WithError(err).Error("Failed to cleanup expired admin_refresh_tokens")
        return err
    }

    logger.Info("Daily token cleanup (expired only) completed successfully.")
    return nil
}