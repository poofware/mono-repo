package seeding

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/poofware/mono-repo/backend/shared/go-models"
	"github.com/poofware/mono-repo/backend/shared/go-repositories"
	"github.com/poofware/mono-repo/backend/shared/go-utils"
)

const (
	DefaultPropertyManagerID = "22222222-2222-2222-2222-222222222222"
)

// SeedDefaultPropertyManager creates the demo property manager account if needed.
func SeedDefaultPropertyManager(pmRepo repositories.PropertyManagerRepository) error {
	ctx := context.Background()
	pmID := uuid.MustParse(DefaultPropertyManagerID)

	if existing, err := pmRepo.GetByID(ctx, pmID); err != nil {
		return fmt.Errorf("check existing property manager: %w", err)
	} else if existing != nil {
		utils.Logger.Info("seeding: default property manager already present; skipping")
		return nil
	}

	pm := &models.PropertyManager{
		ID:              pmID,
		Email:           "team@thepoofapp.com",
		PhoneNumber:     utils.Ptr("+12565550000"),
		TOTPSecret:      "defaultpmstatusactivestotpsecret",
		BusinessName:    "Demo Property Management",
		BusinessAddress: "30 Gates Mill St NW",
		City:            "Huntsville",
		State:           "AL",
		ZipCode:         "35806",
	}
	if err := pmRepo.Create(ctx, pm); err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			utils.Logger.Infof("seeding: property manager (id=%s) already exists; skipping", pmID)
			return nil
		}
		return fmt.Errorf("create default property manager: %w", err)
	}

	if err := pmRepo.UpdateWithRetry(ctx, pmID, func(stored *models.PropertyManager) error {
		stored.AccountStatus = models.PMAccountStatusActive
		stored.SetupProgress = models.SetupProgressDone
		return nil
	}); err != nil {
		return fmt.Errorf("update default property manager status: %w", err)
	}

	utils.Logger.Infof("seeding: created default property manager id=%s", pmID)
	return nil
}
