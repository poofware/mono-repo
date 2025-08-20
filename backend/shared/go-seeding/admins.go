package seeding

import (
	"context"
	"errors"
	"fmt"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v4"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
	"golang.org/x/crypto/bcrypt"
)

func SeedDefaultAdmin(adminRepo repositories.AdminRepository) error {
	ctx := context.Background()
	defaultAdminID := uuid.MustParse("11111111-2222-3333-4444-555555555555")

	// MODIFICATION: Check by ID first, as this is the source of the unique constraint violation.
	existing, err := adminRepo.GetByID(ctx, defaultAdminID)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return fmt.Errorf("error checking for existing admin by ID: %w", err)
	}
	if existing != nil {
		utils.Logger.Infof("Default admin already exists (ID=%s); skipping seed.", existing.ID)
		return nil
	}

	hashedPass, err := bcrypt.GenerateFromPassword([]byte("P@ssword123"), bcrypt.DefaultCost)
	if err != nil {
		return fmt.Errorf("failed to bcrypt-hash default admin password: %w", err)
	}

	totpSecret := "adminstatusactivestotpsecret"

	admin := &models.Admin{
		ID:           defaultAdminID,
		Username:     "seedadmin",
		PasswordHash: string(hashedPass),
		TOTPSecret:   totpSecret,
	}

	if err := adminRepo.Create(ctx, admin); err != nil {
		return fmt.Errorf("failed to insert default admin: %w", err)
	}

	if err := adminRepo.UpdateWithRetry(ctx, admin.ID, func(stored *models.Admin) error {
		stored.AccountStatus = models.AccountStatusActive
		stored.SetupProgress = models.SetupProgressDone
		return nil
	}); err != nil {
		return fmt.Errorf("failed to update default admin status to active: %w", err)
	}

	utils.Logger.Infof("Successfully seeded and activated default admin (ID=%s, username=%s).", defaultAdminID, admin.Username)
	return nil
}

