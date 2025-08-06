// meta-service/services/account-service/internal/app/seed.go

package app

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgconn"
	"github.com/poofware/go-models"
	"github.com/poofware/go-repositories"
	"github.com/poofware/go-utils"
)

// Helper to check for unique violation error (PostgreSQL specific code)
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

/*
	------------------------------------------------------------------
	  Seed a permanent Worker account for Google Play Store reviewers

------------------------------------------------------------------
*/
func SeedGooglePlayReviewerAccount(workerRepo repositories.WorkerRepository) error {
	ctx := context.Background()
	googlePlayReviewerWorkerID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa3333")

	// --- Worker: ACTIVE, setup DONE for Google Play Reviewer ---
	wReviewer := &models.Worker{
		ID:          googlePlayReviewerWorkerID,
		Email:       "play-reviewer@thepoofapp.com",
		PhoneNumber: utils.GooglePlayStoreReviewerPhone,
		TOTPSecret:  "googleplayreviewerworkersecretok",
		FirstName:   "GooglePlay",
		LastName:    "Reviewer",
	}
	if err := workerRepo.Create(ctx, wReviewer); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("Google Play Reviewer Worker already present (id=%s); skipping.", wReviewer.ID)
		} else {
			return fmt.Errorf("insert google play reviewer worker: %w", err)
		}
	} else {
		utils.Logger.Infof("Created Google Play Reviewer Worker id=%s, now updating status.", wReviewer.ID)
		if err := workerRepo.UpdateWithRetry(ctx, wReviewer.ID, func(stored *models.Worker) error {
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
		utils.Logger.Infof("Updated Google Play Reviewer Worker to account_status=ACTIVE and setup_progress=DONE.")
	}
	return nil
}

/*
	------------------------------------------------------------------
	  SeedAllAccounts – unconditionally seeds permanent accounts (e.g. for reviewers).

------------------------------------------------------------------
*/
func SeedAllAccounts(
	workerRepo repositories.WorkerRepository,
	pmRepo repositories.PropertyManagerRepository,
) error {
	ctx := context.Background()
	sentinelID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa3333")
	if w, err := workerRepo.GetByID(ctx, sentinelID); err != nil {
		return fmt.Errorf("check existing reviewer account: %w", err)
	} else if w != nil {
		utils.Logger.Info("account-service: permanent accounts already seeded; skipping")
		return nil
	}

	if err := SeedGooglePlayReviewerAccount(workerRepo); err != nil {
		return fmt.Errorf("seed google play reviewer account: %w", err)
	}
	// In the future, other permanent accounts could be seeded here.
	return nil
}

/*
	------------------------------------------------------------------
	  Seed a default Worker (test/demo purposes only)

------------------------------------------------------------------
*/
func SeedDefaultWorker(workerRepo repositories.WorkerRepository) error {
	ctx := context.Background()
	defaultWorkerStatusIncompleteID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa1111")
	defaultWorkerStatusActiveID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa2222")

	// --- Worker 1: INCOMPLETE, at AWAITING_PERSONAL_INFO step ---
	wIncomplete := &models.Worker{
		ID:          defaultWorkerStatusIncompleteID,
		Email:       "jlmoors001@gmail.com",
		PhoneNumber: "+15551110000",
		TOTPSecret:  "defaultworkerstatusincompletestotpsecret",
		FirstName:   "DefaultWorker",
		LastName:    "SetupIncomplete",
	}
	if err := workerRepo.Create(ctx, wIncomplete); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("Default Worker (incomplete) already present (id=%s); skipping.", wIncomplete.ID)
		} else {
			return fmt.Errorf("insert default worker (incomplete): %w", err)
		}
	} else {
		utils.Logger.Infof("Created default Worker (incomplete) id=%s, now updating status.", wIncomplete.ID)
		if err := workerRepo.UpdateWithRetry(ctx, wIncomplete.ID, func(stored *models.Worker) error {
			stored.StreetAddress = "123 Default Status Incomplete St"
			stored.City = "SeedCity"
			stored.State = "AL"
			stored.ZipCode = "90000"
			stored.VehicleYear = 2022
			stored.VehicleMake = "Toyota"
			stored.VehicleModel = "Corolla"
			// This worker is now at the beginning of the setup flow.
			stored.SetupProgress = models.SetupProgressBackgroundCheck
			return nil
		}); err != nil {
			return fmt.Errorf("update default worker (incomplete) status: %w", err)
		}
		utils.Logger.Infof("Updated default Worker (incomplete) with address and to setup_progress=AWAITING_PERSONAL_INFO.")
	}

	// --- Worker 2: ACTIVE, setup DONE ---
	wActive := &models.Worker{
		ID:          defaultWorkerStatusActiveID,
		Email:       "team@thepoofapp.com",
		PhoneNumber: "+12567013403",
		TOTPSecret:  "defaultworkerstatusactivestotpsecretokay",
		FirstName:   "DefaultWorker",
		LastName:    "SetupActive",
	}
	if err := workerRepo.Create(ctx, wActive); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("Default Worker (active) already present (id=%s); skipping.", wActive.ID)
		} else {
			return fmt.Errorf("insert default worker (active): %w", err)
		}
	} else {
		utils.Logger.Infof("Created default Worker (active) id=%s, now updating status.", wActive.ID)
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
			stored.StripeConnectAccountID = utils.Ptr("acct_1RZHahCLd3ZjFFWN") // Happy Path Connect ID
			return nil
		}); err != nil {
			return fmt.Errorf("update default worker (active) status: %w", err)
		}
		utils.Logger.Infof("Updated default Worker (active) with address and to account_status=ACTIVE, setup_progress=DONE, and added Stripe Connect ID.")
	}
	return nil
}

/*
	------------------------------------------------------------------
	  Seed a minimal PropertyManager record (just the manager account).

------------------------------------------------------------------
*/
func SeedDefaultPropertyManagerAccountOnly(pmRepo repositories.PropertyManagerRepository) error {
	ctx := context.Background()
	pmID := uuid.MustParse("22222222-2222-2222-2222-222222222222")

	// Create a minimal property manager record (no properties).
	pm := &models.PropertyManager{
		ID:              pmID,
		Email:           "team@thepoofapp.com",
		PhoneNumber:     utils.Ptr("+12567013403"),
		TOTPSecret:      "defaultpmstatusactivestotpsecret",
		BusinessName:    "Demo Property Management",
		BusinessAddress: "30 Gates Mill St NW",
		City:            "Huntsville",
		State:           "AL",
		ZipCode:         "35806",
	}
	if err := pmRepo.Create(ctx, pm); err != nil {
		if isUniqueViolation(err) {
			utils.Logger.Infof("Demo Property-Manager already present (id=%s); skipping property manager account seeding.", pmID)
		} else {
			return fmt.Errorf("create minimal PM: %w", err)
		}
	} else {
		utils.Logger.Infof("Seeded minimal property manager record (id=%s).", pmID)
		// Now update status to ACTIVE and DONE
		if err := pmRepo.UpdateWithRetry(ctx, pmID, func(stored *models.PropertyManager) error {
			stored.AccountStatus = models.AccountStatusActive
			stored.SetupProgress = models.SetupProgressDone
			return nil
		}); err != nil {
			return fmt.Errorf("update default PM status: %w", err)
		}
		utils.Logger.Infof("Updated default PM to account_status=ACTIVE, setup_progress=DONE.")
	}

	return nil
}

/*
	------------------------------------------------------------------
	  SeedAllTestAccounts – convenience called from main() or app init.

------------------------------------------------------------------
*/
func SeedAllTestAccounts(
	workerRepo repositories.WorkerRepository,
	pmRepo repositories.PropertyManagerRepository,
) error {
	ctx := context.Background()
	sentinelID := uuid.MustParse("1d30bfa5-e42f-457e-a21c-6b7e1aaa1111")
	if w, err := workerRepo.GetByID(ctx, sentinelID); err != nil {
		return fmt.Errorf("check existing default worker: %w", err)
	} else if w != nil {
		utils.Logger.Info("account-service: test accounts already seeded; skipping")
		return nil
	}
	if err := SeedDefaultWorker(workerRepo); err != nil {
		return fmt.Errorf("seed default worker: %w", err)
	}
	if err := SeedDefaultPropertyManagerAccountOnly(pmRepo); err != nil {
		return fmt.Errorf("seed default property manager account: %w", err)
	}
	return nil
}
