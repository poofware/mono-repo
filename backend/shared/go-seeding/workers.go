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
	DefaultIncompleteWorkerID = "1d30bfa5-e42f-457e-a21c-6b7e1aaa1111"
	DefaultActiveWorkerID     = "1d30bfa5-e42f-457e-a21c-6b7e1aaa2222"
	GooglePlayReviewerWorkerID = "1d30bfa5-e42f-457e-a21c-6b7e1aaa3333"
)


// isUniqueViolation checks for a PostgreSQL unique constraint violation.
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// SeedGooglePlayReviewerWorker ensures the permanent Google Play reviewer worker exists.
func SeedGooglePlayReviewerWorker(workerRepo repositories.WorkerRepository) error {
	ctx := context.Background()
	workerID := uuid.MustParse(GooglePlayReviewerWorkerID)

	if existing, err := workerRepo.GetByID(ctx, workerID); err != nil {
		return fmt.Errorf("check existing reviewer worker: %w", err)
	} else if existing != nil {
		utils.Logger.Info("seeding: Google Play reviewer worker already present; skipping")
		return nil
	}

	w := &models.Worker{
		ID:          workerID,
		Email:       "play-reviewer@thepoofapp.com",
		PhoneNumber: utils.GooglePlayStoreReviewerPhone,
		TOTPSecret:  "googleplayreviewerworkersecretok",
		FirstName:   "GooglePlay",
		LastName:    "Reviewer",
	}
	if err := workerRepo.Create(ctx, w); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("seeding: Google Play reviewer worker already present (id=%s); skipping", w.ID)
			return nil
		}
		return fmt.Errorf("insert google play reviewer worker: %w", err)
	}

	if err := workerRepo.UpdateWithRetry(ctx, w.ID, func(stored *models.Worker) error {
		stored.StreetAddress = "1600 Amphitheatre Parkway"
		stored.City = "Mountain View"
		stored.State = "CA"
		stored.ZipCode = "94043"
		stored.VehicleYear = 2023
		stored.VehicleMake = "Google"
		stored.VehicleModel = "Pixel Car"
		stored.AccountStatus = models.AccountStatusActive
		stored.SetupProgress = models.SetupProgressDone
		return nil
	}); err != nil {
		return fmt.Errorf("update google play reviewer worker status: %w", err)
	}

	utils.Logger.Infof("seeding: Created Google Play reviewer worker id=%s", w.ID)
	return nil
}

// SeedDefaultWorkers seeds the standard demo workers (incomplete and active).
func SeedDefaultWorkers(workerRepo repositories.WorkerRepository) error {
	ctx := context.Background()
	incompleteID := uuid.MustParse(DefaultIncompleteWorkerID)
	activeID := uuid.MustParse(DefaultActiveWorkerID)

	if existing, err := workerRepo.GetByID(ctx, incompleteID); err != nil {
		return fmt.Errorf("check existing default worker: %w", err)
	} else if existing != nil {
		utils.Logger.Info("seeding: default workers already present; skipping")
		return nil
	}

	// Worker 1: setup incomplete
	wIncomplete := &models.Worker{
		ID:          incompleteID,
		Email:       "jlmoors001@gmail.com",
		PhoneNumber: "+15551110000",
		TOTPSecret:  "defaultworkerstatusincompletestotpsecret",
		FirstName:   "DefaultWorker",
		LastName:    "SetupIncomplete",
	}
	if err := workerRepo.Create(ctx, wIncomplete); err != nil {
		if !isUniqueViolation(err) {
			return fmt.Errorf("insert default worker (incomplete): %w", err)
		}
	} else {
		if err := workerRepo.UpdateWithRetry(ctx, wIncomplete.ID, func(stored *models.Worker) error {
			stored.StreetAddress = "123 Default Status Incomplete St"
			stored.City = "SeedCity"
			stored.State = "AL"
			stored.ZipCode = "90000"
			stored.VehicleYear = 2022
			stored.VehicleMake = "Toyota"
			stored.VehicleModel = "Corolla"
			stored.SetupProgress = models.SetupProgressBackgroundCheck
			return nil
		}); err != nil {
			return fmt.Errorf("update default worker (incomplete) status: %w", err)
		}
	}

	// Worker 2: active
	wActive := &models.Worker{
		ID:          activeID,
		Email:       "team@thepoofapp.com",
		PhoneNumber: "+15552220000",
		TOTPSecret:  "defaultworkerstatusactivestotpsecretokay",
		FirstName:   "DefaultWorker",
		LastName:    "SetupActive",
	}
	if err := workerRepo.Create(ctx, wActive); err != nil {
		if !isUniqueViolation(err) {
			return fmt.Errorf("insert default worker (active): %w", err)
		}
	} else {
		if err := workerRepo.UpdateWithRetry(ctx, wActive.ID, func(stored *models.Worker) error {
			stored.StreetAddress = "123 Default Status Active St"
			stored.City = "SeedCity"
			stored.State = "AL"
			stored.ZipCode = "90000"
			stored.VehicleYear = 2022
			stored.VehicleMake = "Toyota"
			stored.VehicleModel = "Camry"
			stored.AccountStatus = models.AccountStatusActive
			stored.SetupProgress = models.SetupProgressDone
			stored.StripeConnectAccountID = utils.Ptr("acct_1RZHahCLd3ZjFFWN")
			return nil
		}); err != nil {
			return fmt.Errorf("update default worker (active) status: %w", err)
		}
	}

	utils.Logger.Info("seeding: seeded default workers")
	return nil
}
