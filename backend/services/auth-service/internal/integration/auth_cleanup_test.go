// meta-service/services/auth-service/internal/integration/auth_cleanup_test.go
//go:build (dev_test || staging_test) && integration

package integration

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	auth_models "github.com/poofware/mono-repo/backend/services/auth-service/internal/models"
	auth_repositories "github.com/poofware/mono-repo/backend/services/auth-service/internal/repositories"
	"github.com/poofware/mono-repo/backend/services/auth-service/internal/services"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

// TestCronJobCleanupServices verifies that the daily cleanup cron jobs for
// expired tokens and verification codes work as expected.
func TestCronJobCleanupServices(t *testing.T) {
	h.T = t
	ctx := context.Background()

	// --- Test Verification Code Cleanup ---
	t.Run("VerificationCodeCleanup", func(t *testing.T) {
		h.T = t
		verificationCleanupService := services.NewVerificationCleanupService(
			 h.PMEmailRepo, h.PMSMSRepo, h.WorkerEmailRepo, h.WorkerSMSRepo,
		)

		// 1. Arrange: Create expired and valid verification codes
		pmEmailRepo := h.PMEmailRepo
		workerSMSRepo := h.WorkerSMSRepo

		// Expired PM Email Code
		err := pmEmailRepo.CreateCode(ctx, nil, "expired-pm-cleanup@test.com", "123456", time.Now().Add(-1*time.Hour))
		require.NoError(t, err)

		// Valid PM Email Code
		err = pmEmailRepo.CreateCode(ctx, nil, "valid-pm-cleanup@test.com", "654321", time.Now().Add(1*time.Hour))
		require.NoError(t, err)

		// Expired Worker SMS Code (verified but old)
		err = workerSMSRepo.CreateCode(ctx, nil, "+15550009999", "111111", time.Now().Add(1*time.Hour))
		require.NoError(t, err)
		_, err = h.DB.Exec(ctx, `UPDATE worker_sms_verification_codes SET verified = TRUE, verified_at = $1 WHERE worker_phone = '+15550009999'`, time.Now().Add(-30*time.Minute))
		require.NoError(t, err)

		// 2. Act: Run the cleanup service
		err = verificationCleanupService.CleanupDaily(ctx)
		require.NoError(t, err)

		// 3. Assert: Check that expired codes are gone and valid ones remain
		_, err = pmEmailRepo.GetCode(ctx, "expired-pm-cleanup@test.com")
		require.Error(t, err, "Expired PM email code should have been deleted")

		validCode, err := pmEmailRepo.GetCode(ctx, "valid-pm-cleanup@test.com")
		require.NoError(t, err)
		require.NotNil(t, validCode, "Valid PM email code should not have been deleted")

		_, err = workerSMSRepo.GetCode(ctx, "+15550009999")
		require.Error(t, err, "Expired (old verified) Worker SMS code should have been deleted")

	})

	// --- Test Token Cleanup ---
	t.Run("TokenCleanup", func(t *testing.T) {
		h.T = t
		pmTokenRepo := auth_repositories.NewPMTokenRepository(h.DB)
		workerTokenRepo := auth_repositories.NewWorkerTokenRepository(h.DB)
		adminTokenRepo := auth_repositories.NewAdminTokenRepository(h.DB)
		tokenCleanupService := services.NewTokenCleanupService(pmTokenRepo, workerTokenRepo, adminTokenRepo)

		// 1. Arrange: Create expired and valid refresh tokens
		pm := h.CreateTestPM(ctx, "token-cleanup-pm")
		worker := h.CreateTestWorker(ctx, "token-cleanup-worker")
		admin := createTestAdminWithPassword(t, ctx, "token-cleanup-admin-"+utils.RandomString(6), "password123")
		defer h.DB.Exec(ctx, `DELETE FROM admins WHERE id=$1`, admin.ID)

		// Expired PM Token
		expiredPMToken := &auth_models.RefreshToken{
			ID:        uuid.New(),
			UserID:    pm.ID,
			Token:     "expired-pm-token-string",
			ExpiresAt: time.Now().Add(-1 * time.Hour),
		}
		err := pmTokenRepo.CreateRefreshToken(ctx, expiredPMToken)
		require.NoError(t, err)

		// Valid Worker Token
		validWorkerToken := &auth_models.RefreshToken{
			ID:        uuid.New(),
			UserID:    worker.ID,
			Token:     "valid-worker-token-string",
			ExpiresAt: time.Now().Add(1 * time.Hour),
		}
		err = workerTokenRepo.CreateRefreshToken(ctx, validWorkerToken)
		require.NoError(t, err)

		// Expired Admin Token
		expiredAdminToken := &auth_models.RefreshToken{
			ID:        uuid.New(),
			UserID:    admin.ID,
			Token:     "expired-admin-token-string",
			ExpiresAt: time.Now().Add(-30 * time.Minute),
		}
		err = adminTokenRepo.CreateRefreshToken(ctx, expiredAdminToken)
		require.NoError(t, err)

		// 2. Act: Run the cleanup service
		err = tokenCleanupService.CleanupDaily(ctx)
		require.NoError(t, err)

		// 3. Assert: Check that expired tokens are gone and valid ones remain
		retrievedExpiredPM, err := pmTokenRepo.GetRefreshToken(ctx, expiredPMToken.Token)
		require.NoError(t, err)
		require.Nil(t, retrievedExpiredPM, "Expired PM refresh token should have been deleted")

		retrievedValidWorker, err := workerTokenRepo.GetRefreshToken(ctx, validWorkerToken.Token)
		require.NoError(t, err)
		require.NotNil(t, retrievedValidWorker, "Valid Worker refresh token should not have been deleted")
		require.Equal(t, utils.HashToken(validWorkerToken.Token), retrievedValidWorker.Token)

		retrievedExpiredAdmin, err := adminTokenRepo.GetRefreshToken(ctx, expiredAdminToken.Token)
		require.NoError(t, err)
		require.Nil(t, retrievedExpiredAdmin, "Expired Admin refresh token should have been deleted")
	})
}